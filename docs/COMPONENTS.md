# Components

Companion to [DEPLOYMENT.md](DEPLOYMENT.md). That document shows *where things
sit and how they wire together*; this one answers, per component: **what it
does, what it's built on, what it talks to, and what happens when it fails.**

Division of labour, so these don't drift: the diagram and its tables are the
topology view. This is the reference view. Versions live in
[TECH_STACK.md](TECH_STACK.md) and are not repeated here.

The **failure mode** line on each card is the one worth reading. This system
runs unattended for weeks; how each piece degrades matters more than how it
behaves when healthy.

## At a glance

| Component | Responsibility | Built on | Arrives |
|---|---|---|---|
| Species camera ×2 | Pixels on animals, tight framing | Dahua IPC-T5442T-ZE | M1 |
| Context camera ×1 | Approach corridors, wide | Reolink RLC-810A / Amcrest | M1 |
| Outdoor PoE switch | Power + data at the yard end | any IP-rated PoE switch | M1 |
| Always-on box | Hosts everything continuous | mini PC or Pi 5, Debian 13 | M1 |
| Edge accelerator | Inference for both model stages | Coral TPU / Hailo-8L | M1 |
| `frigate` | Ingest, motion gate, zones, recording | Frigate + go2rtc | M1 |
| `mosquitto` | The event bus | Eclipse Mosquitto | M1 |
| `falcon-classifier` | Species identification | Python, MegaDetector v6, ONNX | M1 |
| `falcon-brain` | Policy, decisions, audit, API | Python, FastAPI, Pydantic | M1 |
| `falcon-effectors` | Pluggable deterrent interface | Python | M1 (notify only) |
| `falcon-janitor` | Retention enforcement | Python, APScheduler | M1 |
| `ntfy` | Push with action buttons | ntfy (self-hosted) | M1 |
| `falcon.db` | Event and audit store | SQLite (WAL) | M1 |
| `media/` | Crops, sheets, snapshots, clips | filesystem | M1 |
| labeler | Verify crops, export datasets | FastAPI + HTMX | M1 |
| trainer | Fine-tune + evaluate | PyTorch MPS / MLX | M1 |
| ESP32 controller | Drives the physical actuator | ESPHome | M2 |
| Actuator | Water | solenoid / pan-tilt jet | M2 |
| Drone + SITL | Aerial effector | ArduPilot, MAVSDK | M3 (gated) |

---

## Garden

### Species camera ×2

**Does** — Frames an individual bed tightly enough for species ID. Main stream
feeds full-resolution snapshots; sub-stream feeds detection. Onboard
person/vehicle/animal classification can act as a free motion pre-gate.
**Built on** — Dahua/EmpireTech IPC-T5442T-ZE. 1/1.8" sensor, motorized
varifocal, IP67, PoE.
**Consumes** — 802.3af power. **Produces** — RTSP main + sub, ONVIF control.
**Key config** — Zoom/focus set per PLAN.md §5 pixel budget; ≥10 ft mount,
tilted down so the horizon is at or above the top of frame (§5.1).
**Fails by** — Stream drop or PoE loss. Frigate logs decode errors and that
camera goes dark; other cameras are unaffected. Silent failure risk: a knocked
or drifted lens still streams, but at the wrong framing — worth a periodic
snapshot check.

### Context camera ×1

**Does** — Wide view of the whole yard. Cannot do species ID (too few px/ft);
exists to reveal *approach corridors* — which fence line, which tree, whose
yard — which is what tells you where deterrents go in M2.
**Built on** — Reolink RLC-810A or Amcrest IP8M-2496EB, fixed wide lens.
**Fails by** — Same as above, and with lower consequence: nothing in the
decision path depends on it.

### Outdoor PoE switch

**Does** — Terminates the single trenched CAT6 run and fans out to the cameras
(PLAN.md §5.2).
**Fails by** — Takes every garden camera with it. Single point of failure by
design, accepted because the alternative is three trenches.

### ESP32 effector controller *(M2)*

**Does** — Translates an MQTT command into GPIO: relay for a solenoid, PWM for
pan/tilt servos.
**Built on** — ESP32 running ESPHome, declarative YAML config.
**Consumes** — `falcon/actions` over MQTT, or the ESPHome native API.
**Fails by** — Loses WiFi or power and stops actuating. **Must fail closed** —
valve de-energised, jet off. Configure the relay so the un-powered state is
"off", never "on"; a stuck-open valve floods the garden silently.

---

## Always-on box

### The box itself

**Does** — Hosts every continuous part of the system. Deliberately separate
from the MacBook, which sleeps and travels (PLAN.md §6).
**Built on** — Used mini PC (OptiPlex Micro / ThinkCentre Tiny) or Pi 5,
Debian 13, Docker Compose. 500 GB SSD is sufficient under the §11 retention
policy.
**Fails by** — Everything stops. No detection, no logging, no notifications.
Mitigation is boring and effective: Compose `restart: unless-stopped`, and a
dead-man alert (see `falcon-brain`) so silence is distinguishable from "no
critters today."

### Edge accelerator

**Does** — Runs inference for both model stages so the CPU isn't the
bottleneck.
**Built on** — Coral TPU (USB/PCIe) or Hailo-8L via the Pi 5 AI HAT+.
**Fails by** — Frigate and the classifier fall back to CPU where supported:
frame rate collapses, detection latency blows past the §9.4 budget, and events
start being missed rather than misclassified. Degrades quietly — worth an
explicit inference-latency metric.

### `frigate`

**Does** — Pulls RTSP, gates on motion so the accelerator only sees ~1% of
frames, applies zones, records event segments, serves snapshots over HTTP, and
publishes events to MQTT.
**Built on** — Frigate, with go2rtc embedded for restreaming.
**Consumes** — RTSP from cameras. **Produces** — `frigate/events` on MQTT,
clips and snapshots on disk, HTTP API on 5000.
**Key config** — Continuous retention at 0–1 days; event retention ~10 days
(§11.2, §11.6). Detect stream sized per §5.
**Fails by** — No events reach anything downstream, and the pipeline goes
silent rather than wrong. Config is the real hazard: 0.17 shipped breaking
changes with partial auto-migration, so read release notes before bumping.

### `mosquitto`

**Does** — The seam. Every service meets here, which is what makes effectors
pluggable (PLAN.md §7).
**Built on** — Eclipse Mosquitto.
**Topics** — `frigate/events`, `falcon/detections`, `falcon/actions`.
**Fails by** — Total decoupling failure: Frigate still records, but nothing is
classified, decided, or notified. Highest-leverage thing to health-check.

### `falcon-classifier`

**Does** — The two-stage pipeline. Subscribes to `frigate/events`, pulls the
**full-resolution** snapshot from Frigate's HTTP API (the detect sub-stream has
too few px/ft for species ID, §5), runs MegaDetector v6 for presence, then the
species model, and publishes a classified detection.
**Built on** — Python, PytorchWildlife / MegaDetector v6, a fine-tuned
EfficientNet-B0 or YOLO11-s exported to ONNX, ONNX Runtime.
**Consumes** — `frigate/events`, Frigate HTTP. **Produces** —
`falcon/detections`.
**Why a sidecar, not a Frigate plugin** — Frigate 0.17 added native object
classification, so this is a real choice. The sidecar wins because model
iteration never touches NVR config, it needs the full-res snapshot rather than
the detect stream, and swapping models is a container restart.
**Fails by** — Detections stop; Frigate keeps recording, so nothing is lost
permanently and a backfill is possible from retained snapshots. Worse failure
is a *silently degraded* model after a bad deploy — which is why model
provenance hashes are in the event record (§7).

### `falcon-brain`

**Does** — Owns every decision. Applies the engagement policy (§9): target
thresholds, protected-class vetoes, trailing windows, cooldowns, daylight
gating, shadow mode. Writes the audit trail. Serves the HTTP API, including
`POST /sortie` for tap-to-launch. Copies pinned media out of Frigate's
lifecycle (§11.6).
**Built on** — Python, FastAPI, Pydantic (the event contract in §7 is Pydantic
models — one source of truth), paho-mqtt.
**Consumes** — `falcon/detections`. **Produces** — `falcon/actions`, rows in
`falcon.db`, files in `media/pinned/`.
**Fails by** — No decisions and no notifications. **This is the component that
should own the dead-man alert**: if no event has been classified in N daylight
hours, say so — otherwise a dead pipeline is indistinguishable from a quiet
garden, and you discover it a fortnight later with no data.

### `falcon-effectors`

**Does** — One interface, several implementations: notify, sprinkler, audio,
drone. Subscribing to the same topic is what lets M3 stay gated without
blocking anything (§4.2).
**Built on** — Python. Notify is the only implementation in M1.
**Consumes** — `falcon/actions`. **Produces** — HTTP to ntfy, MQTT/ESPHome to
the ESP32, MAVLink to the drone (M3).
**Fails by** — Nothing fires. In M1 that means no push notifications; in M2 no
deterrent. Fails safe in every direction — the dangerous failure would be
firing when it shouldn't, which is why the veto lives in `brain`, upstream.

### `falcon-janitor`

**Does** — Enforces the §11 retention tiers over Falcon's own directories:
expires clips at 7 days, snapshots at 30, contact sheets at a year; never
touches pinned events; writes the daily gzipped NDJSON export.
**Built on** — Python, APScheduler or a systemd timer.
**Fails by** — Disk fills gradually. At ~40 GB/yr steady state you have months
of headroom, so this is a slow, recoverable failure — but add a disk-space
check anyway, because a full disk takes SQLite down with it.

### `ntfy`

**Does** — Push notifications carrying the snapshot and an action button, which
is the mechanism for tap-to-launch (§3).
**Built on** — ntfy, self-hosted.
**Fails by** — No notifications; detection and logging continue unaffected.
Relies on APNs/FCM, the only third-party dependency in M1/M2.

### `falcon.db` and `media/`

**Does** — `falcon.db` is the permanent record: events, full trajectories, all
class scores, decisions, audit. `media/` holds crops (forever), contact sheets
(1 yr), snapshots (30 d), clips (7 d); `media/pinned/` is exempt from all of it.
**Built on** — SQLite in WAL mode; plain filesystem.
**Fails by** — WAL mode survives unclean shutdown well, but the database is the
irreplaceable artifact here. Back it up: it is ~219 MB/year and it *is* the
critter clock. Clips are disposable; this is not.

---

## Off-LAN

### labeler

**Does** — Presents crops for verification, exports training sets. HTMX
specifically to avoid a JS build for one internal page.
**Built on** — FastAPI + HTMX, running on the Mac.
**Fails by** — No consequence to the running system; it's a development tool.

### trainer

**Does** — Fine-tunes the species classifier and evaluates it, notably
`P(predicted ∈ TARGETS | actual = cat)` (§9.5), then exports ONNX for
deployment.
**Built on** — PyTorch MPS or MLX on the M4 Max. Note §10.4: don't run a
training job and a local VLM concurrently — 36 GB is shared.
**Fails by** — No consequence to the running system.

### Phone / APNs / FCM

**Does** — Receives the push, authorizes a sortie. The human in the loop that
makes M3 lawful (§3).
**Fails by** — You stop hearing about events. The system keeps recording and
deciding, so nothing is lost but timeliness.

---

## M3 — gated, not deployed

### Drone + companion computer, ArduPilot SITL

**Does** — The aerial effector and the simulator it is developed against.
**Built on** — ArduPilot, MAVSDK-Python, Gazebo.
**Status** — Gated on the New Jersey wildlife rule (§4.2), not on cost. The
entire sortie state machine, geofence, and abort paths are testable in SITL
with no hardware, so this work is possible regardless of how the legal question
resolves.
