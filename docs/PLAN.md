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
anyway. Also needed: FAA registration if ≥250 g, Remote ID, and LAANC if in
controlled airspace — this address sits under the New York Class B shelf and
roughly 4 NM from Essex County Airport (CDW, Class D), so it is plausibly
inside CDW's surface area. Check the FAA UAS Facility Map / B4UFLY for the
exact grid value; if it is inside, *every* flight needs LAANC, which makes
even tap-to-launch tedious. **And see §4.2 — New Jersey has a wildlife rule
that hits this concept harder than Part 107 does.**

**Class labels.** COCO — what every off-the-shelf detector ships with — has
`bird`, `cat`, `dog`, and no squirrel, chipmunk, or groundhog. Squirrels land
as `cat` or `bird` at mediocre confidence. This needs a real two-stage
pipeline (§5), and that is the single largest piece of work in Milestone 1.

## 4. Site profile — 378 Park St, Montclair NJ

From public parcel/listing records (see §4.3 for what still needs measuring):

| | |
|---|---|
| Lot | 75 × 175 ft, 13,125 sq ft (0.30 ac) |
| Zoning | R1 |
| APN | 13 02605-0000-00019 |
| House | 3,492 sq ft finished, built 1889 |

**Backyard estimate: ~75 ft wide × ~85 ft deep, ~6,400 sq ft gross.** Derived,
not measured: 175 ft of depth less a ~35–40 ft front setback less a ~50 ft
house depth (an 1889 house of this size is typically 2.5 stories over a
~1,400 sq ft footprint, plus a front porch). A detached rear garage and
driveway are common for this vintage in Upper Montclair; if present, usable
yard drops to roughly 5,500–6,000 sq ft.

### 4.1 What the lot width means for the drone

75 ft wide means **the property line is never more than ~37 ft from the
centerline of the yard.** A drone at 20 ft AGL has direct sightlines into two
neighbors' yards, and prop noise at that distance is not subtle. This is a
suburban lot, not a rural one — the drone was always going to be the socially
expensive effector here.

### 4.2 New Jersey wildlife rule — affects the core concept

**N.J.A.C. 7:25-5.32** (NJ Division of Fish & Wildlife, effective May 2018)
prohibits using a drone or other unmanned aircraft to *hunt, trap, **harass**,
scout, **drive**, track, retrieve, or rally* wildlife. Penalties tie to
N.J.S.A. 2C:40-28(b).

"Buzz a squirrel to scare it off" is, on the face of the text, using a drone to
harass and drive wildlife. Squirrels, chipmunks, and groundhogs are wildlife in
NJ. This is the single largest risk to the drone concept as originally framed,
and it is specific to unmanned aircraft — **ground-based deterrents (water,
sound, motion) are not covered by this rule.**

Confidence: consistent across multiple secondary sources; primary regulation
text was not retrievable. Verify against the actual N.J.A.C. text and, if the
drone effector matters, call NJ DEP Fish & Wildlife before building it.

Consequence for this plan: M1 and M2 are unaffected. M3 (drone) moves from
"deferred on cost" to "deferred pending a legal answer," and stays valuable as
a SITL-only exercise regardless. The `Effector` interface means nothing else
has to change.

### 4.3 Open site questions

House depth front-to-back; detached garage/driveway present; which side of Park
St (determines whether the backyard faces east or west, and therefore which
time of day the sun is in frame); mature tree canopy (affects sightlines, IR
illumination, and GPS multipath); available eave mounting points and whether
PoE can be run to them.

## 5. Camera planning — the math that drives everything

The binding constraint is **pixels on a small animal**, and it rules out the
obvious layout.

Target: ~40 px across the animal for reliable species classification.

| Animal | Body length | px/ft needed |
|---|---|---|
| Chipmunk | ~0.4 ft | ~100 |
| Squirrel | ~0.8 ft | ~50 |
| Groundhog | ~1.7 ft | ~25 |

A 4 MP camera is 2560 px wide. At 100 px/ft that buys a **25.6 ft scene
width** — and 8 MP only stretches it to ~38 ft.

**So one camera cannot cover a 75 ft yard.** At full width you get 34 px/ft,
which is 13 px on a chipmunk. Hopeless.

**Cover the beds, not the yard.** A 20-ft bed at 2560 px is 128 px/ft — a
chipmunk is ~51 px, a squirrel ~102. That works. Lens follows from standoff
distance for a ~25 ft scene width:

| Standoff | HFOV needed | Lens (1/1.8" sensor) |
|---|---|---|
| 15 ft | ~80° | ~4 mm |
| 25 ft | ~54° | ~6 mm |
| 35 ft | ~40° | ~8 mm |

Wide-angle 2.8 mm cameras — the default on most bundles — are the wrong
purchase for this entire project.

**Detect-stream caveat.** Frigate runs detection on a sub-stream, typically
1280 px wide, halving all of the above; a chipmunk lands around 20 px. That is
enough for MegaDetector to fire a "something is there" event, but not for
species ID. The classifier sidecar therefore pulls the **full-resolution
snapshot** for stage 2. This is a second, independent reason the sidecar
architecture (§6) beats a Frigate detector plugin.

**Sun.** Park St runs roughly north–south, so the backyard faces east or west
and will take low sun in frame once a day. Mount so cameras look north where
the geometry allows; otherwise put the camera on the sun side shooting away
from it. Confirm which side of the street resolves this.

## 6. Architecture

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

## 7. The detection pipeline

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

## 8. Milestones

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

**Gated on the §4.2 legal question** — resolve that before any hardware
spend. Regardless of the answer, **build this against ArduPilot SITL + Gazebo
first.** The entire sortie state
machine, geofence logic, abort paths, and MAVLink plumbing can be written,
tested, and CI'd with no hardware. Buy the airframe once the software flies in
sim. Platform choice (custom PX4/ArduPilot + Pi companion, vs. Parrot/Olympe)
stays deferred until then — the `Effector` interface hides it either way.

### M4 — Conditioning experiment
Randomized approach vectors, variable delays, audio profile rotation.
Measure raid frequency over 30-day windows against M1's baseline. This is the
only way to know whether any of it worked.

## 9. Repo layout (proposed)

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

## 10. Hardware (M1 only)

- 2–3 PoE cameras with RTSP and a usable sub-stream (Reolink 810A/811A,
  Amcrest, or any Dahua OEM). **Buy for lens, not megapixels** — per §5, a
  4–8 mm lens matched to your standoff distance, never the bundled 2.8 mm.
  Varifocal is worth the premium here since you will re-aim these while
  tuning. Wide dynamic range matters more than resolution — midday sun plus
  bed shadow is the hard case.
- PoE switch/injector, outdoor-rated cable runs.
- The GPU box you already have.
- Total: roughly $200–400.

No drone spend until M3, and none at all until the software flies in SITL.

## 11. Open questions

Site-specific ones are in §4.3. Still open and affecting the build: the
never-target list (pets, bird feeder, neighbors' cats), whether night
operation is needed, language/deploy preferences for the non-CV services, and
the time budget.

Resolved: tap-to-launch posture (§3), ground-effector-first (§8), GPU box
available, M1 scope (§8).
