# Falcon — garden critter deterrence

A vision system that watches the garden, identifies which animal is in it, and
escalates to a deterrent. The drone is one deterrent among several, not the
foundation.

Status: planning. Nothing built yet.

## 1. The core design decision

Separate **watching** from **scaring**. They have opposite requirements:

| | Watching | Scaring |
|---|---|---|
| Duty cycle | 24/7 | seconds, a few times a day |
| Must be | cheap, static, reliable | fast, loud, *unpredictable* |
| Good platform | fixed PoE cameras | sprinkler, sound, drone |
| Bad platform | drone (20 min battery, loud, weather-bound) | fixed camera |

A drone cannot do the watching — it would have to already be airborne when the
squirrel arrives. So: **fixed cameras detect, an event bus carries the
decision, and effectors are pluggable behind one interface.** The drone becomes
`DroneEffector` alongside `SprinklerEffector`, and it can be added or removed
without touching the detection half.

This also means ~80% of the system (the interesting software) gets built and
validated before any airframe is purchased.

## 2. Why a drone is still worth doing

Animals habituate. A motion-activated sprinkler works for about two weeks, an
ultrasonic emitter for less, a plastic owl for about four hours. The literature
on deterrence is consistent: the variable that predicts durability is
*unpredictability*, not intensity.

A drone that approaches from a different vector each time, at a randomized
delay, with a randomized audio profile, is one of the few deterrents that
resists habituation. That is the real argument for it — not response latency,
which it will lose at (see §3).

## 3. Three constraints that shape everything

**Latency.** A chipmunk's visit is 5–20 s. Cold-pad launch to on-target is
realistically 8–15 s. The drone will often arrive after the animal has left.
Design consequence: the drone's job is *conditioning over weeks*, not saving
today's tomato. Judge it on raid frequency at day 30, not on individual
intercepts. Fast effectors (water, sound) handle the immediate event.

**Regulation (US).** A camera-triggered launch with nobody watching is
specifically what is not allowed — Part 107 requires a pilot in command and
visual line of sight, and "protecting my garden" is a purpose, which likely
pushes it out of the recreational §44809 carve-out. Design consequence, and the
chosen posture: **tap-to-launch.** Detection pushes a snapshot with an action
button; a human taps; the sortie flies while that human watches. Fully
compliant, and costs ~10 s of reaction time the system was going to lose
anyway. Also needed: FAA registration if ≥250 g, Remote ID, LAANC if in
controlled airspace.

**Class labels.** COCO — what every off-the-shelf detector ships with — has
`bird`, `cat`, `dog`, and no squirrel, chipmunk, or groundhog. Squirrels land
as `cat` or `bird` at mediocre confidence. This needs a real two-stage
pipeline (§5), and that is the single largest piece of work in Milestone 1.

## 4. Architecture

```
  PoE cam ─┐
  PoE cam ─┼─► Frigate ──MQTT──► classifier ──► brain ──► effectors
  PoE cam ─┘   (decode,          (Mega-        (policy,    ├─ notify  (ntfy)
               motion gate,       Detector →    cooldown,   ├─ sprinkler
               zones, NVR,        SpeciesNet    escalation, ├─ audio
               snapshots)         / our own)    audit log)  └─ drone (tap-to-launch)
                                       │            │
                                       └──► event store (SQLite + clips on disk)
                                                    │
                                              labeler UI → training set → fine-tune
```

**Frigate** does ingest, motion gating, zones, recording, and snapshot serving.
Do not rewrite this. It gates on motion so the GPU only sees ~1% of frames.

**classifier** is a sidecar, not a Frigate detector plugin. It subscribes to
`frigate/events`, pulls the snapshot over Frigate's HTTP API, and runs the real
model. Keeping it out of Frigate means model iteration doesn't touch NVR
config, and the model can be swapped or A/B'd freely.

**brain** owns policy: per-species response, cooldowns, escalation ladder,
never-target list, quiet hours, and the audit log. Every effector action is a
row.

The whole thing runs in Docker Compose on the GPU box.

## 5. The detection pipeline

Stage 1 — **is there an animal.** MegaDetector (Pytorch-Wildlife) is built for
exactly this: camera-trap imagery, three classes (animal / person / vehicle),
very high recall in bad light and partial occlusion. Far more robust here than
a COCO detector.

Stage 2 — **which animal.** Two options, use both in sequence over time:
- *Bootstrap:* SpeciesNet, which covers North American rodents, gets you
  useful labels on day one with zero training.
- *Converge:* fine-tune a small classifier (EfficientNet-B0 or YOLO11-s) on
  crops from your own cameras. A fixed camera is an enormous advantage — the
  background is constant, so 2–3k verified crops gets high accuracy quickly.

Stage 3 — **labeling flywheel.** Every event stores its crop. Auto-label with
an open-vocabulary detector (YOLO-World or OWLv2, prompted with
`["squirrel","chipmunk","groundhog","rabbit","deer","cat","dog","bird","human"]`),
then human-verify in a minimal web UI. Verifying a few hundred crops is one
evening. This is what makes the system yours rather than generic.

Optional slow path: a VLM on the snapshot as an out-of-band second opinion for
low-confidence events. Not in the latency path — used to catch systematic
errors and to prioritize what to label next.

### Event contract

One schema, stable across all phases, so effectors written now still work when
the drone lands:

```json
{
  "event_id": "uuid",
  "ts": "2026-09-20T14:22:11.482Z",
  "camera": "bed_north",
  "zone": ["tomatoes"],
  "species": "squirrel",
  "confidence": 0.91,
  "bbox": [0.31, 0.44, 0.09, 0.14],
  "world": { "bearing_deg": 118.0, "range_m": 6.2 },
  "track_id": "t-9931",
  "dwell_s": 4.2,
  "snapshot_uri": "file:///var/falcon/snap/…jpg",
  "clip_uri": "file:///var/falcon/clip/…mp4"
}
```

`world` is populated by a per-camera homography (one calibration per camera,
ground-plane assumption). It is unused in M1 and essential the moment an
effector needs to aim.

## 6. Milestones

### M1 — Detect, notify, log  ← current
Cameras mounted, Frigate ingesting, two-stage classifier running, every event
stored with crop + clip, push notification with snapshot, labeler UI, first
fine-tune. **No actuators at all.**

Deliverable that matters: a **critter clock** — which species, which beds,
what time of day, how often. You cannot tune a deterrent you haven't measured,
and this dataset is the input to every later decision.

Exit criteria: ≥95% recall on squirrel/chipmunk/groundhog, <1 false push/day,
≥14 days of continuous logging.

### M2 — Ground effector, closed loop
`SprinklerEffector` via a relay/solenoid (ESPHome or a plain GPIO relay board).
Proves the end-to-end latency budget and gives a genuinely effective deterrent
immediately. Escalation ladder, cooldowns, never-target list, and the
randomization policy all get built and tested here — with a device that cannot
crash into anything.

A pan/tilt water jet (2 servos + solenoid, aimed from `world.bearing_deg`) is
the highest effect-per-dollar actuator in the whole project and worth
considering before the drone.

### M3 — Drone, tap-to-launch
Notification gains a **Launch** action → `POST /sortie` → scripted flight →
FPV stream to phone → auto-RTL. Hard geofence, battery floor, abort button,
and a propeller-guard requirement.

**Build this against ArduPilot SITL + Gazebo first.** The entire sortie state
machine, geofence logic, abort paths, and MAVLink plumbing can be written,
tested, and CI'd with no hardware. Buy the airframe once the software flies in
sim. Platform choice (custom PX4/ArduPilot + Pi companion, vs. Parrot/Olympe)
stays deferred until then — the `Effector` interface hides it either way.

### M4 — Conditioning experiment
Randomized approach vectors, variable delays, audio profile rotation.
Measure raid frequency over 30-day windows against M1's baseline. This is the
only way to know whether any of it worked.

## 7. Repo layout (proposed)

```
falcon/
├─ docs/           PLAN.md, adr/, calibration notes
├─ services/
│  ├─ ingest/      Frigate config, camera definitions, zones
│  ├─ classifier/  MegaDetector → species, MQTT in/out
│  ├─ brain/       policy, escalation, audit log, HTTP API
│  └─ effectors/   notify, sprinkler, audio, drone
├─ packages/
│  └─ schemas/     the event contract, one source of truth
├─ tools/
│  ├─ labeler/     verify crops, export dataset
│  └─ train/       fine-tune + eval scripts
└─ deploy/         compose.yaml, .env.example
```

## 8. Hardware (M1 only)

- 2–3 PoE cameras with RTSP and a usable sub-stream (Reolink 810A/811A,
  Amcrest, or any Dahua OEM). Wide dynamic range matters more than resolution —
  midday sun plus bed shadow is the hard case.
- PoE switch/injector, outdoor-rated cable runs.
- The GPU box you already have.
- Total: roughly $200–400.

No drone spend until M3, and none at all until the software flies in SITL.

## 9. Open questions

Tracked in the conversation; the ones that change the build:
yard geometry and mounting points, jurisdiction and airspace class, the
never-target list, night operation, language/deploy preferences, and
time budget.
