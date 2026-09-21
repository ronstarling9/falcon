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

The evidence is stronger than "plausible." Six years of grizzly-bear hazing
(163 events) puts drones at **91% success**, ahead of vehicle pursuit and
projectiles, with signs of genuine aversive conditioning over years rather
than habituation; artificial-predator drones show no measurable habituation in
bird flocks. Sources and the mechanism — *approach* is what separates a drone
from a scarecrow — are in **§11.5**.

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

House depth front-to-back; detached garage/driveway present; **mature tree
canopy** — it affects sightlines and dappled-shade false positives, and §10.7
makes it the fact that decides whether a clear drone transit altitude exists
at all; **whether a rear garage or shed has power** — the single fact that decides
whether §5.2 needs a trench at all; mounting points at the **west end** of the
lot — fence
posts, a garage, a shed — since that is where the cameras now go (§5.1); and
the cable route for the run in §5.2.

Resolved: house is on the west side of Park St, front door east, so the
backyard faces west.

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
architecture (§7) beats a Frigate detector plugin.

### 5.1 Siting — the sun and the neighbors agree

The house is on the **west** side of Park St with the front door facing east,
so **the backyard faces west**. At 40.83° N the sun sets at azimuth ~302°
(WNW) in June, 270° in September, ~238° (WSW) in December — all of it down
the length of the yard.

**Do not mount the cameras on the back of the house.** A camera on the west
wall looking west into the yard takes the low afternoon sun straight down its
optical axis, from roughly 15:00 to sunset — which is peak foraging time. Lens
flare, blown highlights, and useless WDR exactly when you need the frames.

**Mount at the west (far) end of the lot, looking east back toward the
house.** Then the afternoon sun is behind the camera and the animals are
front-lit: the best-lit configuration available on this lot. Morning sun is in
that direction, but a west-facing yard sits in the house's own shadow until
the sun clears the roofline — roughly 19° elevation for a 30 ft house seen
from 85 ft away.

**The general rule that solves the rest: keep the sky out of the frame.**
Mount at 10–12 ft and tilt down far enough that the horizon sits at or above
the top of frame. At ~20° downtilt with a 40° vertical FOV, nothing above the
horizon is in shot, so the sun is excluded at both ends of the day regardless
of azimuth — and the camera stops metering against a bright sky, which is what
was destroying dynamic range in the first place. This costs nothing; it is
purely a mounting decision.

**The same siting is also the privacy-correct one.** Cameras at the back fence
aimed east look at *your own house*. A camera on the house aimed west would be
pointed directly into the rear neighbor's property. Same mount, best light,
least intrusion — take it.

### 5.2 Getting power and data to the beds

A west-facing yard is shaded by its own house for the first 30–40 ft each
morning, so full-sun vegetable beds are almost certainly in the **rear half**,
40–85 ft out. Per §5 the pixel budget allows a ~25 ft standoff at 4 MP —
nowhere near 85 ft. So the cameras live out at the beds.

**Backyard WiFi is available, but it solves data, not power** — and power is
the binding constraint.

*Why battery and solar cameras don't rescue this.* Battery cameras (Argus,
Wyze and similar) are architecturally incompatible with this design: they
sleep, wake on PIR, take 1–3 s to start streaming, and expose no continuous
RTSP. This system needs a continuous sub-stream for motion gating and a
sub-second decision budget. Solar doesn't close the gap either — a camera
streaming continuously draws ~5–8 W, and even restricted to the daylight
window (§8) that's ~70–140 Wh/day, against maybe 40–60 Wh/day from a small
panel in a partly-treed NJ yard in December. Off by several times in the
season that matters least, workable only in midsummer, and by the time you've
bought panel plus battery plus charge controller you've spent more than the
trench.

So mains power has to reach the yard end regardless, which means digging.

**And once you're digging, PoE is the easy thing to put in the hole.** Running
120 V out there is the harder job: direct-burial UF-B or conduit at code
depth, GFCI protection, probably an electrician and possibly a permit. A
single direct-burial CAT6 is low-voltage, needs none of that, and carries
power *and* data in one run. **PoE isn't the expensive option here — it's the
cheap one.**

Topology: one 60–90 ft direct-burial CAT6 in conduit out to a small
outdoor-rated PoE switch at the yard end, then short jumpers to each camera.
One trench, one conduit, one switch.

*Even with power solved, PoE still wins on the link itself.* Three cameras
running main plus sub streams is ~15–20 Mbps sustained, 24/7. WiFi carries
that in good conditions — but this is a 75 ft lot in dense suburbia, through
an exterior wall, across 60–90 ft, with summer leaf-out attenuating both bands
and every neighbor's AP competing for airtime. Frigate is unforgiving of
stream instability (decode errors, fragmented recordings), and retransmit
jitter eats the latency budget. Dropouts will correlate with exactly the
frames you care about.

**The one fact that changes this:** if there's a detached garage or shed at
the rear with existing power — plausible for an 1889 Upper Montclair house
with a driveway — then power is already solved, WiFi becomes reasonable, and
the trench disappears. This is the open item in §4.3 worth answering first.

**Don't let any of this block M1.** A WiFi camera on an outdoor extension cord
to a rear GFCI outlet is a perfectly good throwaway prototype, and a temporary
fence-line run is a normal way to do a growing-season-only deployment. Get
data flowing, validate that the models separate squirrel from chipmunk on
*your* footage, and trench later once the system has earned it.

## 6. Compute topology — the Mac is not the server

The available GPU is a 2024 MacBook Pro, M4 Max, 32-core GPU with 36 GB
unified memory (full specs in [TECH_STACK.md](TECH_STACK.md)). That is a lot
of compute, but it is the wrong shape for half of this system, and the
mismatch is worth stating plainly because it invalidates "run the whole stack
in Compose on the GPU box."

**Why a laptop can't be the always-on half:**

- It sleeps when the lid closes, and it leaves the house. M1's entire
  deliverable is *14+ days of uninterrupted logging*.
- **Docker on macOS runs in a Linux VM with no access to the Apple GPU.**
  Containers cannot reach Metal. There is also no VAAPI/NVDEC for video
  decode, and VideoToolbox isn't exposed to the VM — so a containerized
  Frigate on this machine gets neither accelerated inference nor accelerated
  decode. Frigate does not meaningfully support macOS.

**So split it:**

| | Always-on box | MacBook Pro |
|---|---|---|
| Runs | Frigate, classifier sidecar, brain, effectors | labeler, training, evaluation |
| Needs | 24/7 uptime, cheap, edge accelerator | big GPU, unified memory |
| Cost | ~$120–250 | owned |

**Always-on box options**, cheapest first: a used mini PC (Dell OptiPlex
Micro, Lenovo ThinkCentre Tiny — ~$100–150 and plenty for 2–3 streams) with a
Coral TPU; or a Raspberry Pi 5 with the AI HAT+ (Hailo-8L, 13 TOPS), which is
a clean fit for Frigate. Either way, sizing the inference for an edge
accelerator is the constraint: MegaDetector quantized, plus a small
fine-tuned classifier (EfficientNet-B0 or MobileNetV3) at int8. Both fit.

A cheap trick that cuts the always-on compute requirement substantially: most
Reolink/Dahua cameras do person/vehicle/**animal** classification onboard. Use
that as the motion gate and the box only ever sees frames that already have an
animal in them.

**The Mac's actual job is the better one.** Fine-tuning the species classifier
on a few thousand crops is exactly what a large unified-memory Apple GPU is
good at — MLX or PyTorch MPS, both pleasant. MegaDetector is PyTorch and runs
on MPS; the SpeciesNet bootstrap pass is offline, so CPU fallback is fine if
its ops don't map cleanly.

**Zero-spend start.** Develop the entire pipeline natively on the Mac right
now against clips from the Nest Cam already on hand (§16.1) or any video file — no Docker, no hardware. Buy the
always-on box only when you're ready to run continuously. That defers all
spend past the point where you know the pipeline works.

## 7. Architecture

```
  PoE cam ─┐
  PoE cam ─┼─► Frigate ──MQTT──► classifier ──► brain ──► effectors
  PoE cam ─┘   (decode,          (Mega-        (policy,    ├─ notify  (ntfy)
               motion gate,       Detector →    cooldown,   ├─ sprinkler
               zones, NVR,        SpeciesNet    escalation, ├─ audio
               snapshots)         / our own)    audit log)  └─ drone (tap-to-launch)
                                       │            │
                                       └──► event store (SQLite + media on disk)
                                                    ▲
                                              janitor (§13 tiers)
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

The always-on half runs in Docker Compose on the small box (§6), not on
the Mac. Full deployment view — nodes, containers, protocols and ports — is in
**[DEPLOYMENT.md](DEPLOYMENT.md)** (UML source: `deployment.puml`);
per-component detail in **[COMPONENTS.md](COMPONENTS.md)**; pinned versions in
**[TECH_STACK.md](TECH_STACK.md)**.

## 8. The detection pipeline

### 8.1 What each model can actually do out of the box

| Model | Classes | What it gives you here |
|---|---|---|
| COCO detectors (Frigate default) | 80 | **Nothing.** No squirrel, chipmunk or groundhog class exists. A squirrel is forced into `cat`, sometimes `bird`. This is a *vocabulary* problem, not a confidence problem — no threshold creates a class that isn't there. |
| **MegaDetector v6** | 3 (animal/person/vehicle) | Reliably finds the animal — ~99.4% at "is something there" — and tells you nothing about which. By design: it's a blank-frame filter for camera-trap researchers. |
| **SpeciesNet** | **2,498** | **This one can.** EfficientNetV2-M trained on 65M labelled camera-trap images, covers North American rodents, and geofences predictions to species that actually occur at your coordinates. |

So the honest answer to "can it work out of the box" is **plausibly yes**, via
SpeciesNet. Fine-tuning is not a given.

### 8.2 So why might you still need to fine-tune? Domain shift

SpeciesNet is trained on *camera-trap* imagery: ground-level, motion-triggered,
animal usually large in frame, often IR-lit. Yours is a security camera 10–12 ft
up, tilted ~20° down, in daylight, with the animal 25–40 ft away at 50–100 px
(§5). Different angle, scale, optics and colour science.

The camera-trap literature puts accuracy loss under domain shift at
**9% to 60%.** That range is the whole question. You might land at the good
end and never need to train anything; you might land at the bad end. **You
cannot know without measuring, and measuring is cheap.**

### 8.3 Escalation ladder — stop as soon as it's good enough

Each step costs more than the one above it. Most projects stop at 3.

1. **SpeciesNet as-is, geofenced** to your lat/long. Free. Measure.
2. **Restrict the label space** to your ~8 local species by masking logits.
   Not fine-tuning. Large accuracy win for almost no work — a model choosing
   among 2,498 classes will occasionally pick a plausible-but-absurd Eurasian
   rodent.
3. **Recalibrate per-class thresholds** for the asymmetric loss in §9.5. Not
   fine-tuning either, and it targets the metric that actually governs safety
   rather than average accuracy.
4. **Fine-tune SpeciesNet's head** on your own crops. ← only now
5. Fine-tune deeper, or train a custom detector. Rarely needed.

**If you reach step 4, fine-tune SpeciesNet — don't train your own model.**
The 2026 literature finds fine-tuned SpeciesNet outperforms locally-trained
models, because you keep global feature representations and add only local
taxonomic specialisation. There is a close precedent: AHDriFT-ID fine-tuned
SpeciesNet to 46 categories for *downward-facing small-animal cameras* in
Ohio — similar geometry, similar animals, similar region.

### 8.4 What fine-tuning actually is, mechanically

You are not retraining a network. The backbone already knows edges, fur
texture and animal morphology from 65M images; you keep all of that and
retrain only the final classification layer(s) to map those features onto
*your* label set and *your* imaging conditions. That's why thousands of
examples suffice rather than millions.

The loop:

1. **Collect** — automatic. M1 stores every crop, so the training set accrues
   as a side effect of running the system.
2. **Auto-label** — SpeciesNet plus an open-vocabulary detector propose labels;
   you are never labelling from scratch.
3. **Verify** — confirm/correct in the labeler. The only expensive step, and
   it's an evening or three.
4. **Dedup** — by embedding (§12.3). 3,000 near-identical crops are not 3,000
   examples.
5. **Split** — see the traps below.
6. **Train the head** — minutes to an hour on the M4 Max.
7. **Evaluate** — on `P(predicted ∈ TARGETS | actual = cat)` (§9.5), not
   accuracy.
8. **Export** — ONNX, int8, deploy to the box.
9. **Iterate** — new failures become new training data.

### 8.5 Two traps

**Split by time, not at random.** A single squirrel visit yields ~50
near-identical frames. A random split scatters them across train and test, the
model effectively sees its test set during training, and your reported accuracy
is fiction. Split by day or by week.

**Crop tightly to the detection box — and note this qualifies something said
earlier.** A fixed camera's constant background is a data-efficiency advantage,
*and* an overfitting hazard: the model can learn "brown blob on that fence post
= squirrel" instead of what a squirrel looks like, score beautifully on your
test set, and fail the first time one appears somewhere new. The literature's
remedy is exactly this — crop to the MegaDetector box so the model sees the
animal rather than the habitat. Cropping is what converts the fixed background
from a liability into an advantage.

### 8.6 Labeling flywheel

Every event stores its crop. Auto-label with an open-vocabulary detector
(YOLO-World or OWLv2, prompted with
`["squirrel","chipmunk","groundhog","rabbit","deer","cat","dog","bird","human"]`),
then human-verify. Verifying a few hundred crops is one evening. This is what
makes the system yours rather than generic — and per §8.3, you should only
reach for it once measurement says steps 1–3 weren't enough.

### Detection window — daylight only

Night operation is **out of scope**. Gate the whole pipeline on a solar
schedule (civil dawn → civil dusk; in Montclair that swings from ~05:20–20:45
in June to ~07:00–17:00 in December). This is a real simplification, not just
a deferral:

- No IR illuminators, no low-light camera premium, no separate night training
  set — IR imagery is a different domain and would roughly double the
  labeling work.
- Roughly half the events disappear, and with them the worst false-positive
  source (IR-lit insects and spiderwebs at the lens, which dominate nighttime
  motion events on every outdoor camera).
- It fits the target list exactly: squirrels, chipmunks, and groundhogs are
  all diurnal.

**Known gap to accept consciously:** raccoons and opossums are nocturnal, deer
are crepuscular. If damage appears overnight, the M1 baseline will be blind to
the cause and cannot explain it. Dawn/dusk edges also still mean low sun and
long shadows, so wide dynamic range on the cameras still matters.

Optional slow path: a VLM on the snapshot as an out-of-band second opinion for
low-confidence events. Not in the latency path — used to catch systematic
errors and to prioritize what to label next. Expanded in §12.

### Event contract

One schema, stable across all phases, so effectors written now still work when
the drone lands:

```json
{
  "event_id": "uuid",
  "track_id": "t-9931",
  "camera": "bed_north",
  "first_seen": "2026-09-20T14:22:11.482Z",
  "last_seen":  "2026-09-20T14:22:15.704Z",
  "dwell_s": 4.2,

  "species": "squirrel",
  "confidence": 0.91,
  "scores":    { "squirrel": 0.91, "chipmunk": 0.05, "rabbit": 0.02 },
  "protected": { "person": 0.00, "dog": 0.01, "cat": 0.11, "bird": 0.03 },

  "models": {
    "stage1": "megadetector-v6c@sha256:1f3a…",
    "stage2": "species-clf@v4:sha256:9b02…"
  },

  "zones": [{ "name": "tomatoes", "enter": 1.10, "exit": 3.90 }],
  "track": [[0.31,0.44,0.09,0.14], [0.33,0.44,0.09,0.14], "…50 points @5Hz"],
  "world": {
    "frame": "site-enu",
    "position_m": { "x": 7.42, "y": -3.10, "z": 1.22 },
    "sigma_m":    { "horizontal": 0.28, "vertical": 0.35 },
    "method": "stereo",
    "surface": "fence_rail",
    "surface_ambiguous": true,
    "truncated": false,
    "bearing_deg": 118.0,
    "range_m": 6.2
  },

  "context": { "sun_elev_deg": 31.2, "sun_az_deg": 244.0, "solar_phase": "pm" },

  "decision": {
    "engage": false,
    "reason": "veto:cat",
    "rule": "protected_veto",
    "thresholds": { "engage": 0.80, "cat": 0.05 }
  },
  "effector": {
    "kind": "drone",
    "fired_at": "2026-09-20T14:22:16.110Z",
    "passes": 1,
    "min_standoff_m": 3.1,
    "broke_off": "target_left_zone",
    "outcome": { "displaced": true, "displace_latency_s": 2.8, "return_latency_s": 941 },
    "sortie_budget": { "today": 3, "max_per_day": 6 }
  },

  "media": {
    "crop_uri":    "file:///var/falcon/crop/…jpg",
    "sheet_uri":   "file:///var/falcon/sheet/…jpg",
    "snapshot_uri":"file:///var/falcon/snap/…jpg",
    "clip_uri":    "file:///var/falcon/clip/…mp4",
    "clip_expires":"2026-09-27T14:22:11Z"
  },
  "retention": { "tier": "standard", "pinned": false, "pin_reason": null }
}
```

`track` is the field that earns the short clip retention (§13.4): the full
bbox path at detection rate is ~1 KB and reconstructs speed, entry edge, and
approach vector without any video. `models` records provenance so a later
re-analysis knows which model version produced which label.

`world` is the field that turns a detection into something an effector can
aim at, and it carries its own uncertainty on purpose: a ground-plane
homography is exact for an animal on the lawn and wrong by 10–15 ft for one on
a fence rail or a deck. `method`, `sigma_m` and `surface_ambiguous` are what
the launch gate actually reads — see **§10**, which is the whole story. Unused
in M1; load-bearing from M2 onward.

## 9. Engagement policy — the never-target list drives the design

Protected: **dogs, cats, children, birds.**

### 9.1 Protected classes are a veto, not a competing label

The instinct is to let the classifier pick a winner and engage if it says
"squirrel." That is wrong here, because the error costs are wildly asymmetric:
missing one squirrel costs nothing, soaking a child is unacceptable. So
detection of a target and detection of a protected class run as **two
independent tests with different thresholds**, and the protected test is a
veto that wins regardless of margin.

Concretely: `squirrel 0.82, cat 0.11` must **not** engage. A cat at 0.11 is
far too much cat. Veto thresholds belong down around 0.02–0.10 while the
engage threshold sits at 0.80.

### 9.2 "Children" means person — never build a child classifier

Detect **person** and veto on any person at all, at any age. Don't try to
distinguish child from adult: it's harder, less reliable, and pointless, since
you don't want to spray adults either. MegaDetector's person class already has
very high recall, which is exactly the property a veto needs.

This is both the safer design and the simpler one.

### 9.3 Birds are the hard case, and they create a real tension

Birds are the single largest false-positive source on any outdoor garden
camera — constant, small, fast motion. Putting them on the veto list is
fail-safe in the right direction (a bird detection suppresses rather than
triggers). But a naive trailing-window veto on birds means the system
**never fires**, because in a Montclair backyard in July there is essentially
always a bird within a few seconds of the frame.

So birds get different veto semantics from mammals: **spatial only, no
trailing window.** Veto if a bird is near the aim point right now; don't hold
the veto after it leaves.

Worth stating consciously: birds *do* eat gardens. Excluding them is a
preference, not an oversight — it just means the system will never address
that share of the damage, and the M1 baseline should track bird activity
separately so you can see how large that share is.

### 9.4 The decision function

Engagement requires **positive evidence and absence of veto evidence and
freshness**. Any missing input means no engagement — a failed classifier, a
stale frame, or an unreachable protected-class check all fail closed.

```
engage(frame) iff ALL:
  fresh     now - frame.ts < 1.0 s
  positive  max P(species in TARGETS) >= 0.80
  stable    same species across >= 3 consecutive frames within 0.75 s
  clear     for each p in PROTECTED: P(p) < veto_threshold[p]
            AND no PROTECTED sighting within trailing_window[p]
  policy    cooldown elapsed, inside daylight window, effector armed
else        log the decision with its reason, do not engage
```

| Protected class | Veto threshold | Trailing window |
|---|---|---|
| person | 0.02 | 120 s |
| dog | 0.05 | 60 s |
| cat | 0.05 | 60 s |
| bird | 0.10 | none — spatial only (§9.3) |

Trailing windows exist because cameras have blind spots: a dog that left frame
two seconds ago is still in the yard.

The `stable` requirement costs ~0.5 s of latency and eliminates most
single-frame errors. That's an easy trade for a water jet; revisit only if a
faster effector ever justifies it.

Start with **frame-level** vetoes (protected class anywhere in frame). Move to
spatial vetoes (protected class within the effector's hazard cone around the
aim point) only once tracking is trustworthy.

### 9.5 The specific technical risk: cat ↔ squirrel

COCO-trained detectors routinely label squirrels as `cat`. One direction of
that confusion is harmless — a squirrel read as a cat just suppresses. The
**other direction soaks a cat**, so it is the number that matters:

> Named exit criterion for M2: **P(predicted ∈ TARGETS | actual = cat) ≈ 0**,
> measured on a held-out set with cats deliberately over-represented.

Overall accuracy is not the metric. This conditional is.

### 9.6 You will have to farm negatives deliberately

The self-collected dataset will be badly imbalanced exactly where it matters.
Your cameras will capture thousands of birds, a handful of cats, and almost no
dogs or children — the protected classes are rarest precisely where errors are
most expensive.

So stage the capture: walk the kids and the dog through the garden on camera
for a few sessions, from varied distances and angles, at different times of
day. A few hundred frames each. Supplement cats with public imagery, but the
staged on-camera frames matter more because they match your exact lighting,
background, and geometry.

This is a real M1 task, not an afterthought.

### 9.7 Shadow mode before live fire

M2's policy runs for a week in **dry-run**: evaluate every decision, log
"would have engaged" with the snapshot that triggered it, actuate nothing.
Then review every would-have-fired event by hand.

This is how you find the cat-read-as-squirrel *before* it hits a cat, and it
costs a week and zero dollars. Do not skip it.

## 10. Target designation and flight guidance

The camera gives you a pixel. The flight controller wants a position.
Everything in this section lives between those two sentences.

**Scope note.** Elevated targets — fence rails, deck rails, lawn chairs — are
out of engagement scope (§11). The surface model below is still worth
building, but its job is now to *recognize and reject* an off-ground detection
rather than to fly to one, and §10.1 is why: a ground-plane estimate for an
elevated animal isn't merely imprecise, it is confidently wrong by 10–15 ft.

### 10.1 The projection problem — and why §7's homography is not enough

A detection is a box in image space, `(u, v, w, h)`. Every pixel defines a
**ray** out of the camera's optical center, and the animal is somewhere along
it. Which point along it is exactly the depth that was destroyed when the
scene was projected onto the sensor. You get it back only by adding an
assumption or another measurement.

The cheap assumption is the ground plane. Calibrate once: lay 4+ markers on
the lawn, measure their positions with a tape, click their pixel coordinates,
solve a 3×3 homography with `cv2.findHomography`. Then take the
**bottom-center of the bounding box** — the contact point where feet meet
ground — and `[x y w]ᵀ = H · [u v 1]ᵀ`. With a 10–12 ft mount and honest
calibration that is good to roughly ±0.3 m at 8 m, degrading with range
because the viewing angle flattens: far out, one pixel of vertical error
sweeps a lot of ground.

**Fence post, deck, lawn chair — those break it, and the error is not
small.** Homography assumes z = 0. For a camera at height `H` and an animal
standing at true height `h`, true horizontal distance `d`, the ray continues
past the animal and strikes the ground at

```
d' = d · H / (H − h)
```

With a 12 ft camera:

| Where it actually is | h | d | Homography says | Error |
|---|---|---|---|---|
| Lawn, driveway | 0 ft | 25 ft | 25.0 ft | — |
| Raised bed edge | 1 ft | 25 ft | 27.3 ft | 2.3 ft |
| Lawn chair back | 3 ft | 15 ft | 20.0 ft | 5.0 ft |
| Deck surface | 3.5 ft | 25 ft | 35.3 ft | **10.3 ft** |
| Fence rail | 4 ft | 25 ft | 37.5 ft | **12.5 ft** |
| Deck rail | 3.5 ft | 35 ft | 49.4 ft | **14.4 ft** |

The drone doesn't miss by a little. It flies to a point ten to fifteen feet
*past* the animal, which on a 75 ft lot can be over the neighbor's fence.

So: **one homography is fine for a pan/tilt water jet aiming at ground beds
(§14/M2), and disqualifying for a drone.** §7 now says so.

### 10.2 Fix 1 — a 2.5D site model instead of a single plane

Don't assume one plane; enumerate them. This yard has six to ten surfaces an
animal can stand on, and they are all flat quads:

| Surface | Height | Note |
|---|---|---|
| lawn | 0.00 m | the default |
| driveway | 0.00 m | may be graded — measure, don't assume |
| raised bed edge | 0.30 m | |
| deck | 1.07 m | |
| fence rail | 1.22 m | a *line*, not an area — worst ambiguity |
| deck rail | 1.98 m | narrow, and the favorite perch |
| garage roof | ~3 m | never a target, but it's the approach route |

Targeting becomes a raycast instead of a matrix multiply: build the ray from
the pixel, intersect it with every surface, keep the **nearest hit in front of
the camera**. That is the surface the animal is standing on, because anything
behind it is occluded by definition.

This is about thirty lines of code, and it is the Frigate zone concept you
already have (§7 `zones`) extended by exactly one number — give a zone a
height and it becomes a surface. Keep the polygons in a local metric frame,
versioned under `services/brain/site/`: this is site truth, not config.

Two honest limits, and both push toward fix 2. **The lawn chair moves** — so
do the wheelbarrow, the hose reel, and the bag of mulch. And a ray that grazes
a fence rail is numerically nasty: two pixels of error flips you between "on
the rail at 8 m" and "on the lawn at 14 m."

### 10.3 Fix 2 — two cameras, and the depth comes back

§5 already puts two species cameras on the lot. When both see the animal at
the same instant you need no surface assumption at all: intersect the two rays
and you have a true 3D point. This is the robust answer, and the hardware cost
is zero because the hardware is already in the plan.

What it does cost:

- **Extrinsic calibration** — the rigid transform between the cameras. Image a
  set of shared markers with known positions and solve `cv2.solvePnP` per
  camera against the same world frame. Redo it whenever a camera is bumped,
  and treat a bump as an incident rather than a shrug.
- **Time sync.** The rays must come from *simultaneous* frames. A squirrel at
  1.5 m/s with 150 ms of inter-camera skew is 22 cm of error before you start.
  Run NTP on both cameras, use RTSP presentation timestamps, and only fuse
  detections whose timestamps agree to <50 ms. Reject the pair otherwise.
- **Overlap.** Stereo only exists inside the intersection of the two frusta.
  Aim the overlap deliberately at the beds and the deck — where the surface
  ambiguity is worst — and accept monocular fallback elsewhere.

Two rays never actually meet, so take the midpoint of their mutual
perpendicular and use that segment's length as a free quality signal: if the
rays pass more than ~0.5 m apart, you have probably fused two different
animals. Drop it.

### 10.4 Therefore a position is a distribution, not a point

All of the above argues for the same change to the event contract. `world`
stops being two scalars and starts carrying its own provenance and
uncertainty:

```json
"world": {
  "frame": "site-enu",
  "position_m": { "x": 7.42, "y": -3.10, "z": 1.22 },
  "sigma_m":    { "horizontal": 0.28, "vertical": 0.35 },
  "method": "stereo",
  "surface": "fence_rail",
  "surface_ambiguous": true,
  "bearing_deg": 118.0,
  "range_m": 6.2
}
```

`method` ∈ `stereo | surface | ground_plane | unknown`. The launch gate reads
`method` and `sigma_m` — **not** `position_m`. That is the whole safety
argument in one line: `surface_ambiguous`, or σ above threshold, is an
**abort**, not a guess. A confidently wrong position is far more dangerous
than an admittedly unknown one.

And define the frame first. `site-enu` is a local East-North-Up metric frame
whose origin is a physical, findable monument — a bolt in the dock pad. Every
camera calibration, every site polygon, and the drone's home position resolve
into that one frame. Write it down in `docs/adr/` before any calibration work,
or you will spend a weekend reconciling three coordinate conventions that are
each individually correct.

### 10.5 Getting the drone there — don't navigate to the animal

Here is the reframe that makes the whole problem tractable. **The drone does
not need to know where the squirrel is. It needs to get close enough that its
own camera can see it, and then close the loop itself.**

That changes the accuracy requirement from "±0.3 m" to "put the target inside
the drone's field of view" — at a 10 m standoff with a 70° FOV, a ±4 m box.
Every method above clears that easily, *including plain homography on the
lawn*. Structure the sortie as a handoff:

1. **Cue** — fixed cameras emit `world.position_m` ± σ.
2. **Transit** — fly to a **standoff** waypoint: offset horizontally and
   *above* the target, chosen so the ambiguity cone — σ, plus the surface
   ambiguity, plus however far the animal has moved since the cue — fits
   inside the drone's FOV.
3. **Acquire** — the drone's own detector finds the animal in its own frames.
4. **Servo** — approach on the drone's own bearing. This needs no site model,
   no homography, and no GPS.
5. **Abort** — no acquisition within N seconds → RTL. Treat this as the
   *expected* outcome, not a failure.

This is why the fixed cameras never have to be good at ranging, and why
arguing about ±20 cm is the wrong argument to have.

### 10.6 What the flight controller actually navigates in

ArduPilot and PX4 navigate in GPS/NED, so `site-enu` has to be georeferenced:
survey the origin once, store lat/lon/alt, convert waypoints to offsets. But
look at what that asks of GPS in a 23 × 26 m yard hemmed in by a house and
trees — consumer GPS with multipath off a wall is 2–5 m, the same order as the
entire target area. In rough order of sanity:

- **Don't use GPS for guidance at all.** Optical flow plus a downward
  rangefinder dead-reckons very well over 25 m and is genuinely more accurate
  than GPS at this scale.
- **Fiducials.** A few AprilTag/ArUco markers on the fence and the dock give
  absolute drift correction, and the dock tag doubles as ArduPilot precision
  landing. This is a printed sheet of paper.
- **RTK.** Centimeter-grade, ~$300–600 for base + rover, and the most moving
  parts. Almost certainly overkill here — noted so it can be dismissed
  deliberately.

The non-obvious consequence: on a lot this small, the flight controller's
default (trust GPS) is the *least* accurate option available. Don't let a
default make that call.

### 10.7 The obstacle question — four problems wearing one name

"Something between the dock and the critter" is four different failure modes
with four different fixes.

**(a) Known static obstacles** — house, garage, fence, pergola, clothesline, a
mature maple. These go into the same site model as the surfaces (§10.2), with
heights. The fix is geometric rather than algorithmic: **climb–cruise–
descend.** Take off vertically to a transit altitude above everything, fly
horizontally, descend over the target. Delivery and survey aircraft do this
because vertical clearance is enormously cheaper than 3D path planning — one
number replaces a planner.

That works *if a clear transit altitude exists*. A 6 ft fence and a 9 ft deck
umbrella are both cleared at 20 ft. **Tree canopy is what decides it, and it
is the §4.3 question this section makes load-bearing.** A mature maple
overhanging the yard means no single clear altitude exists, and you are into
real 3D planning (ArduPilot BendyRuler or Dijkstra against a proximity map)
for a hobby aircraft in a 23 m yard. If that is the situation, better to know
it now: it may be the fact that ends the drone branch in favor of the pan/tilt
jet. **Measure the canopy before buying an airframe.**

One static obstacle deserves naming on its own: **utility drops and
clotheslines are effectively invisible** — to every sensor a small drone can
carry, and to the pilot. Map them by hand.

**(b) Unknown and moving obstacles** — a person, a dog, a thrown ball,
laundry, a branch that came down last week. The site model cannot help; the
drone needs its own sensing. Minimum viable is a downward rangefinder
(VL53L1X or a small lidar) so altitude never depends on the barometer, plus
forward proximity. ArduPilot's avoidance stack consumes proximity input and
offers either simple avoidance (stop/slide) or a full planner. Configure it to
**stop**, not to route around: stopping is analyzable and route-around is not.

**(c) Occlusion in the fixed camera's own view** — the subtle one, and it
corrupts *targeting* rather than flight. If the squirrel is behind the deck
rail with only its head showing, the bottom of the bounding box is the
**rail**, not its feet — so the contact point is wrong and the position
estimate is confidently wrong. Catch it: if the box's bottom edge lies on a
known occluder boundary, or the box is clipped by the frame edge, set
`truncated: true` and either fall back to the stereo estimate or abort. This
is the check that catches the dangerous class of error from §10.4.

**(d) Obstacles to things that are not the drone.** The house is an RF
obstacle — an aircraft behind the garage can lose its control link, so define
the failsafe explicitly (RTL, not land-in-place). And Part 107 requires *you*
to hold visual line of sight: the deck umbrella between you and the aircraft
is a compliance problem rather than a technical one, and it is part of why §3
chose tap-to-launch with a human outside watching.

### 10.8 The time budget — the part that may change the concept

Worth stating plainly, because it bounds everything above:

| Step | Time |
|---|---|
| Detect → classify → decide | 0.3–1.0 s |
| Dock open, arm, spin up | 5–10 s |
| Climb to transit altitude | 3–5 s |
| Transit ~20 m | 4–6 s |
| Descend, acquire, servo | 5–10 s |
| **Total** | **~20–35 s** |

Chipmunk dwell at a bed is often under ten seconds. **The drone will
routinely arrive after the animal has left.** That is not a tuning problem, it
is physics, and no amount of guidance precision fixes it.

Two consequences, both already in the plan and now better motivated. It is
why §14/M2's ground effector comes first: a solenoid responds in under a
second, and a pan/tilt jet aims straight off `world.bearing_deg` with no
flight at all. And it recasts what the drone is *for* — not interception, but
the unpredictable moving presence of §2. An aircraft that turns up 25 seconds
later, from a direction that varies, is a **patrol**, and patrols work through
expectation rather than through hits. Design the sortie for *presence over the
bed* rather than *arrival at the fence post*, and the guidance requirement
relaxes by an order of magnitude.

## 11. The effect — what the drone actually does

Scope for this section: **elevated targets are out of scope.** Fence rails,
deck rails and lawn chairs stop being engagement targets; §10's surface model
stays, but only to *reject* those detections rather than fly to them. Targeting
is ground-plane, in the beds, good enough. And the working assumption is that
the animal is usually gone before the aircraft arrives.

Both assumptions are right, and they simplify the flight problem
considerably. They also change what the drone is *for*, which is what this
section is about.

### 11.1 It never touches the animal

This is the one property that has to be structurally impossible rather than
carefully avoided.

- Props against a 500 g squirrel is broken props and a crash. A 3 kg
  groundhog is worse.
- It injures the animal. The never-target list (§9) exists because you care
  about that; the target list doesn't suspend it.
- It converts "deterrence" into "harassment," which is the exact word the
  §4.2 question turns on.
- A cornered groundhog stands and fights, and groundhogs are a rabies vector
  in New Jersey. Never create that encounter.

So the entire effect happens at a distance, and the minimum standoff is a
**geofence floor enforced in the flight code**, not a rule the pilot follows.

### 11.2 How close it *can* get — the altitude floor

Four constraints set the floor, and the binding one is not the animal:

| Constraint | Implied floor |
|---|---|
| Ground effect / downwash instability | ~1 rotor diameter — 0.3–0.5 m for a 5″ quad. Not binding. |
| Rangefinder + altitude-hold error over grass | ±0.2–0.3 m, so ≥1 m of margin |
| Downwash blasting soil and seedlings | noticeable below ~1.5 m |
| **Tomato cages, stakes, trellises, bean poles** | **1.5–2 m — this is the binding one** |

**2 m AGL over open lawn, 3–4 m over planted beds.** The drone hovers *above*
the tomato cages; it never descends among them. Encode it as a per-zone floor
in the site model (§10.2), so the bed polygons carry their own ceiling of
obstacles and the floor is data rather than a constant.

### 11.3 How close it *will* get — the animal decides, not you

The useful result from the gray-squirrel escape literature is that **flight
initiation distance rises with distance to refuge**: a squirrel far from a
tree flees early, one at the base of the maple lets you get close because
escape costs it a second.

That maps directly onto this problem. The beds — the only place you care
about — are by definition away from refuge, so that is exactly where the
animal flees at the longest distance. And the place where it *would* let you
get close is the tree line, where you should not be flying anyway.

Expect a flight response somewhere in the **5–15 m** band of approach, and
expect the aircraft to essentially never close inside 3 m of an animal.
Your assumption is correct, and it's the design working rather than failing.

### 11.4 What actually produces the flight response

Ranked by how much work each does:

1. **Looming.** An object growing in the visual field on a descending
   trajectory is the aerial-predator escape trigger. It is the strongest cue
   available and it costs nothing — it is a trajectory choice, not a payload.
   **Descend toward the animal; don't translate at constant altitude.** A
   stoop from 6 m to the floor is the effect.
2. **Noise.** A small quad is ~68 dB(A) at 10 m, ~78 at 3 m, ~82 at 2 m —
   broadband plus a strong blade-pass tone. Loud, directional, and unlike
   anything else in a suburban yard.
3. **Shadow and motion.** A moving overhead shadow, free, and it works
   precisely in the daylight window §8 already restricts you to.
4. **Audio payload, optional.** A 30 g speaker. Raptor calls are the obvious
   choice, but **conspecific alarm calls are the more interesting one** —
   squirrel kuks and quaas recruit the animal's own signalling system rather
   than asking it to believe in a hawk that isn't there. Rotate the library:
   one fixed sound is the fastest component here to habituate.
5. **Water** — the only genuine aversive on the list. See §11.6.

Not worth carrying: strobes (useless in daylight, and night is out of scope),
ultrasonic emitters (the pest-repeller industry's most reliably debunked
product), and anything that makes contact.

### 11.5 Habituation — the evidence is better than I assumed

This is the question that decides whether any of it is worth building, so it
deserves real evidence rather than a hunch.

- **Grizzly-bear hazing, six years, 163 events** (Sarmento, *Frontiers in
  Conservation Science*, 2025): drones succeeded in **91%** of hazing events,
  against 85% for vehicle pursuit and 74% for projectiles; dogs were far
  worse. More importantly it appears to have *conditioned* — older bears
  required less hazing, events per year declined, and bears fled to locations
  farther from roads and development.
- **RobotFalcon vs. bird flocks**: no evidence of habituation over the
  fieldwork period.
- The disturbance literature is the same finding with the sign flipped —
  terrestrial mammals show disturbance responses to drones below ~60 m AGL,
  and some species habituate quickly.

Sources:
[drones vs. dogs for hazing bears](https://www.frontiersin.org/journals/conservation-science/articles/10.3389/fcosc.2024.1478450/full) ·
[RobotFalcon bird deterrence](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9597169/) ·
[distance-to-refuge and flight initiation distance in gray squirrels](https://www.sfu.ca/biology/faculty/dill/publications/dandH.pdf) ·
[GUARD, an autonomous deer-deterrence UAV](https://arxiv.org/abs/2505.10770) ·
[drone disturbance of colonial breeding birds](https://pmc.ncbi.nlm.nih.gov/articles/PMC12588502/)

The synthesis worth internalizing: **a scarecrow habituates because it is
static and consequence-free.** A drone that *approaches*, from a direction
that varies, after a delay that varies, reads as a pursuing predator instead
of scenery. That is the mechanism, and it is why §14/M4's randomization is the
active ingredient rather than a refinement.

### 11.6 Conditioning — the one genuinely good idea available here

The drone is a **conditioned stimulus**; water is the **unconditioned
aversive**. Pair them and the drone keeps working long after the novelty is
gone.

Except the timing is backwards, which falls straight out of §10.8: the
sprinkler fires in under a second and the drone arrives at 25, so water
*precedes* the aircraft and conditions nothing. Three ways out:

- **(a) Delay the water to the drone's arrival** during an explicit
  `conditioning_mode`. Costs you the fast response for a few weeks; buys a
  durable association. A config flag, not a redesign.
- **(b) Put the water on the drone.** A 100 mL reservoir plus a diaphragm
  pump is ~150–200 g and delivers 20–30 mL. Stimulus and consequence
  co-located, no timing problem. But a drone that *sprays* an animal is much
  more plainly "harassment" than one that merely flies near it — this option
  is gated harder on §4.2 than the rest of M3.
- **(c) Don't condition — alternate.** Sprinkler on most raids, drone on a
  random minority. Unpredictability without pairing. Weakest, simplest, no new
  hardware, no new legal exposure.

Start at **(c)**, measure with §14/M4, escalate to (a) if the data shows
habituation. Take (b) only with a legal answer in hand.

### 11.7 The sortie — arrival behavior and break-off

Written for the common case, which is an empty bed:

```
arrive at standoff (3–6 m above, offset, §10.5)
  ├─ target acquired?
  │    yes → one descending pass toward it, break off at the zone floor
  │          re-acquire; two passes maximum
  │    no  → loiter/sweep the bed 10–20 s on a randomized track
  └─ RTL
```

Two hard rules, both of which are cheaper than the alternative:

**No pursuit.** A fleeing squirrel runs *to* a tree or a fence; following it
at low altitude is how you fly into one. Break off the instant the target
crosses a geofence edge, closes on an obstacle polygon, or leaves the bed.
Deterrence only has to make the bed unattractive — it does not have to win the
chase.

**Two passes without flight is an abort, logged.** An animal that doesn't
flee is cornered, defending young, sick, or genuinely habituated, and all four
are reasons to stop rather than press. This is simultaneously the humane rule,
the legally defensible one (the line between deterring and harassing), and the
one that keeps you from descending onto an angry groundhog.

### 11.8 The budget that will actually constrain this: noise

~78 dB(A) at 3 m, several times a day, in a yard with neighbors about 25 ft
away. Montclair has a noise ordinance and the neighbors have an opinion, and
between them they are far more likely to end this project than any technical
problem in the preceding ten sections.

So budget it as policy in `brain`, not as good intentions:

- max sorties per day (start at 6)
- max sortie duration (60 s)
- minimum inter-sortie gap (20 min)
- a quiet window that isn't only night — Sunday mornings
- a per-animal cap, so one stubborn groundhog can't generate twenty sorties

And note the free mitigation: **the sprinkler is silent.** Every raid the
ground effector handles is a sortie you don't fly, which is the thing that
keeps the drone politically survivable.

### 11.9 What to measure — not proximity, not hits

Three numbers, all against M1's baseline (§14):

- **Displacement** — did the animal leave the bed zone within N seconds of
  the effector firing?
- **Return latency** — time until the next detection of that species in that
  bed.
- **Raid rate** — detections per bed per day over 30-day windows.

**Return latency is the leading indicator.** It shortens before the raid rate
moves, so it's where habituation shows up first and where you'll see whether
conditioning is working while there's still time to change the approach.

## 12. Where an LLM fits — and where it must not

Two hard rules first, because they eliminate the tempting answers:

**Never in the latency path.** The decision budget is sub-second (§9.4). Even a
local 7B VLM is 1–3 s per image, and a cloud call adds a network round trip.
An LLM cannot be the thing that decides to fire.

**Never the safety veto.** The protected-class check (§9.1) must be fast,
deterministic, and measurable. A non-deterministic model that might describe a
cat differently on two consecutive frames is the wrong tool for the one
decision where being wrong is unacceptable.

With those settled, the useful roles are all **offline or out-of-band**, which
is exactly where the Mac lives (§6).

### 12.1 Ranked by value

**1. Shadow-mode review assistant (§9.7).** You have to hand-review a week of
"would have engaged" decisions before live fire. A VLM pre-triages that queue:
flag the ones whose snapshot doesn't match the predicted label, cluster the
failures, surface patterns ("most false positives are the fence post at
16:40"). It doesn't replace your review — it orders it, so the hour you spend
looks at the informative cases first. Biggest labor saving in the project.

**2. Labeling bootstrap and active learning (§8, stage 3).** Pre-label crops so
human verification becomes confirm/correct rather than type-a-name. Then close
the loop: rank unlabeled crops by classifier uncertainty, have the VLM propose
labels for the most uncertain, and verify those first. That is standard active
learning and it is where the labeling time actually goes.

**3. Low-confidence adjudication.** The slow path already in §8: a second
opinion on events the classifier wasn't sure about, out of band, to catch
systematic errors and build the eval set. Never in the decision loop.

**4. Natural-language query over the event log.** Text-to-SQL against
`falcon.db`: *"every groundhog in bed 2 before 09:00 last week."* The M1
deliverable is understanding the baseline (§9), and exploratory questions are
how that actually happens. Low risk — worst case is a wrong query you can read.

**5. Weekly digest.** Narrative summary with representative frames. Pleasant,
marginal.

### 12.2 The caveat that matters

**General VLMs are mediocre at fine-grained small-object recognition.**
Telling an eastern gray squirrel from a chipmunk in a 50 px crop is precisely
the task where a purpose-trained classifier beats a generalist — SpeciesNet and
your own fine-tune (§8) will outperform any VLM here, and the VLM will be
confidently wrong often enough to matter.

So the VLM proposes and assists; it is never ground truth, and it never
replaces stage 2. Treat its labels as a prior to be confirmed.

### 12.3 The better non-LLM answer: embeddings

Worth more than items 3–5 combined, and often overlooked: run an image
embedding model (DINOv2, SigLIP, or CLIP via ONNX) over every crop.

- **Dataset dedup.** After a month you will have thousands of near-identical
  crops of the same squirrel on the same fence post. Train on that and you have
  a 3,000-image dataset with maybe 400 images of information. Embedding
  clustering finds the duplicates before they poison the fine-tune.
- **"Find similar events"** in the labeler — label one, label its whole
  cluster.
- **Cheap novelty detection.** A crop far from every known cluster is either a
  new species or a new failure mode. Both are worth looking at.

This is small, fast, runs on the always-on box, and improves the thing the
whole project depends on.

### 12.4 Running it on the Mac

MLX is the Apple-native runtime and currently the fastest way to run these on
Apple Silicon; **mlx-vlm** is the vision-model wrapper. Ollama is the
lower-friction alternative.

**36 GB unified memory resolves the choice, and it lands right at the
boundary.** Qwen3-VL-30B-A3B (4-bit MLX) wants ≥32 GB: ~15–17 GB of weights
plus the vision encoder, KV cache and image tokens puts the working set near
20 GB, against 36 GB total with macOS taking 4–8 GB. **It fits — but it is the
top of what this machine holds, not a comfortable fit.** Two consequences:

- macOS caps GPU-wired memory at roughly 75% of RAM (~27 GB here). If
  allocation fails, raise it: `sudo sysctl iogpu.wired_limit_mb=30720`.
- **Don't run the VLM and a fine-tune concurrently** — serialize them. Both
  want the same pool.
- Fall back to a Qwen3-VL 8B-class model if it thrashes.

**Throughput: expect ~50 tok/s, not the ~68 tok/s usually quoted for "M4
Max."** Token generation is memory-bandwidth-bound and the 32-core M4 Max is
the binned part at **410 GB/s**, against 546 GB/s on the 40-core version.
Since every LLM role here is batch and offline (§12.1), this is a throughput
number, not a responsiveness one — it doesn't matter much.

Fine-tuning the species classifier is untroubled by any of this: EfficientNet-B0
and YOLO11-s are small, and 36 GB of unified memory allows generous batch sizes.

**The Neural Engine is not the path.** MLX targets the GPU; the 16-core ANE is
only reachable through CoreML. Not worth chasing for batch work.

### 12.5 If you'd rather not run it locally

Cost is not the reason to go local. Adjudicating ~40 low-confidence events a
day is ~44K input tokens plus ~4K output:

| Model | Per month | One-time 3K-crop bootstrap |
|---|---|---|
| `claude-opus-5` ($5/$25 per MTok) | ~$10, or ~$5 batched | ~$13, ~$7 batched |
| `claude-haiku-4-5` ($1/$5 per MTok) | ~$2, or ~$1 batched | ~$2.70, ~$1.40 batched |

The Batch API is 50% off and this workload is entirely asynchronous, so use it.
Prompt caching helps too — the instruction prefix and few-shot examples are
identical across every call, so put them before the image.

**The real argument for local is privacy, not cost.** These cameras point at
your own house (§5.1), your kids are on the never-target list (§9.2), and staged
capture sessions (§9.6) mean deliberately recording your family. That is the
consideration worth weighing, and it is a genuine one — the dollars are noise
either way.

## 13. Data retention

Optimized for: **short video life, permanent detailed records.**

### 13.1 The key ratio

A 30 s clip of a squirrel at 4 MP is ~15 MB. The 224×224 crop cut out of it is
~20 KB. For *training* purposes those contain nearly the same information —
the clip is ~750× larger and adds only motion context and human-reviewable
behavior.

So the design principle is: **keep the crop and the record forever; keep the
clip only as long as you're actively reviewing it.**

### 13.2 Never record continuously

Continuous recording is ~75 GB/day (§16) for no benefit — nothing happens in
99% of those frames. Record detection segments only. In Frigate that means
setting continuous retention to 0–1 days and relying on event-based retention
(`record.alerts.retain.days` / `record.detections.retain.days`;
verify the key names against 0.18, config changed across 0.17).

### 13.3 Tiers

Assuming ~200 detection events/day across three cameras in the daylight window:

| Tier | Size/event | Retention | Steady state |
|---|---|---|---|
| **Event record** (SQLite row + trajectory) | ~3 KB | **forever** | 219 MB/yr |
| **Crop** (224², best + 1 alt) | ~40 KB | **forever**, deduped (§12.3) | 2.9 GB/yr |
| **Contact sheet** (9 sampled frames, one montage JPEG) | ~150 KB | **1 year** | 11 GB |
| **Full-res snapshot** | ~800 KB | **30 days** | 4.8 GB |
| **Clip** (30 s H.265) | ~15 MB | **7 days** | 21 GB |
| **NDJSON daily export** (gzipped) | — | **forever** | 55 MB/yr |

**Total steady state: ~40 GB**, against ~2.3 TB for naive continuous recording
at 30-day retention. Roughly a 60× reduction, and it changes what you need to
buy (§16).

**The contact sheet is the trick.** Nine frames sampled across the event,
tiled into one JPEG, is 1% of the clip's size and preserves the behavioral
sequence — approach, pause, flee. It answers "what actually happened" for
almost every event you'd otherwise pull the video for.

### 13.4 What makes the record detailed enough to replace video

This is the part that earns the short clip retention. Each event row carries:

- **Identity** — `event_id`, `track_id`, camera, `first_seen`, `last_seen`,
  `dwell_s`
- **Full classification** — not just top-1: every class score, plus every
  protected-class score (§9.4)
- **Model provenance** — the version/hash of each model that produced the
  labels, so a later re-analysis knows what labeled what
- **Trajectory** — the *whole* bbox track at detection rate, not one box. 50
  points × 4 floats ≈ 1 KB, and it reconstructs path, speed, entry edge, and
  approach vector. This is what substitutes for watching the clip.
- **Zones** — entered/exited with timestamps; dwell per zone
- **World frame** — `bearing_deg`, `range_m` from the camera homography (§7)
- **Decision** — engage/no-engage, the reason, which rule fired, and the
  threshold values in effect at the time
- **Effector outcome** — what fired, when, for how long
- **Context** — sun elevation and azimuth, position in the solar window;
  optionally temperature and precipitation, which strongly predict activity

**Two log streams, don't conflate them.** Event records are structured,
permanent, and queryable. *Application* logs (service stdout) are transient —
rotate at 7 days / 100 MB and let them go.

For grep-ability alongside SQL, write a **daily NDJSON export, gzipped**. 200
events × 3 KB compresses to ~150 KB/day — 55 MB/year, keep it forever. You get
`zgrep` over the full history and `falcon.db` for real queries, from one
source of truth.

### 13.5 Pinning — retention's exceptions

Some events must ignore the tiers. **Pinned events never auto-delete** (clip
retained 90 days, everything else forever):

1. **Anything the policy acted on** — an effector fired, or shadow mode said it
   would have (§9.7). This is the audit record; if the system ever soaks
   something it shouldn't, this is the evidence.
2. **Any protected-class detection near a decision** (§9.1) — same reason.
3. **Stage disagreements** — MegaDetector vs. species model, or the VLM
   adjudicator vs. the classifier (§12.1). These are the training-valuable
   events.
4. **Manually flagged** in the labeler.

Pins are rare — a handful a day — so they cost little.

### 13.6 Don't fight Frigate's retention engine

Frigate manages its own media lifecycle and will happily delete a clip the
policy wanted pinned. So: give Frigate a **short, generous-enough** window
(~10 days), and have `falcon-brain` **copy pinned media out of Frigate's
managed storage** into `media/pinned/` on write.

A `falcon-janitor` job then enforces §13.3 over Falcon's own directories only.
Two systems, two storage areas, one owner each — rather than two retention
engines arguing over the same files.

## 14. Milestones

### M1 — Detect, notify, log  ← current
Cameras mounted, Frigate ingesting, two-stage classifier running, every event
stored with crop + clip, push notification with snapshot, labeler UI, first
a measured decision on whether fine-tuning is even needed (§8.3), and staged
capture sessions for the protected classes (§9.6).
**No actuators at all.** Bootstrap the dataset offline from the existing Nest
Cam (§16.1) before buying anything.

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
considering before the drone. It is also the cheapest possible test of §10's
targeting math: a jet that misses wastes water, so it is the right place to
measure homography error, validate the site model, and prove the stereo
solution before anything flies.

M2 is also where the camera calibration work lands — homography per camera,
the 2.5D surface model, and the stereo extrinsics (§10.2–10.3). None of it
needs an aircraft.

Exit criteria: one week of shadow mode reviewed by hand (§9.7), and
P(predicted ∈ TARGETS | actual = cat) ≈ 0 on a cat-heavy held-out set (§9.5).

### M3 — Drone, tap-to-launch
Notification gains a **Launch** action → `POST /sortie` → scripted flight →
FPV stream to phone → auto-RTL. Hard geofence, battery floor, abort button,
and a propeller-guard requirement.

Guidance, standoff waypoints, the abort ladder and the obstacle model are
**§10** — the launch gate reads `world.method` and `world.sigma_m`, never
`world.position_m`. What the aircraft actually does on arrival, the altitude
floor, the break-off rules and the noise budget are **§11**.

Exit criteria: 100 SITL sorties with zero floor violations and zero geofence
breaches; the two-passes-without-flight abort (§11.7) exercised in sim;
a sortie budget enforced in `brain` (§11.8); and displacement + return latency
(§11.9) logged for every sortie from the first live flight.

**Gated on the §4.2 legal question** — resolve that before any hardware
spend, along with the §10.7 canopy measurement, which decides whether a clear
transit altitude exists at all. Regardless of the answer, **build this against ArduPilot SITL + Gazebo
first.** The entire sortie state
machine, geofence logic, abort paths, and MAVLink plumbing can be written,
tested, and CI'd with no hardware. Buy the airframe once the software flies in
sim. Platform choice (custom PX4/ArduPilot + Pi companion, vs. Parrot/Olympe)
stays deferred until then — the `Effector` interface hides it either way.

### M4 — Conditioning experiment
Randomized approach vectors, variable delays, audio profile rotation — the
active ingredient, not a refinement (§11.5). Measure displacement, return
latency and raid rate over 30-day windows against M1's baseline (§11.9). This
is the only way to know whether any of it worked.

Start in the un-paired regime (§11.6c): sprinkler on most raids, drone on a
random minority. If return latency starts shortening, that's habituation, and
`conditioning_mode` (§11.6a) is the next move — not a bigger drone.

## 15. Repo layout (proposed)

```
falcon/
├─ docs/           PLAN.md, DEPLOYMENT.md, COMPONENTS.md, TECH_STACK.md,
│                  deployment.puml + renders, adr/, calibration notes
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
├─ tools/render-diagrams.sh
└─ deploy/         compose.yaml, .env.example
```

## 16. Hardware (M1 only)

- 2–3 PoE cameras with RTSP and a usable sub-stream — see the shortlist in
  §16.2. **Buy for lens, not megapixels** (§5), and start with one.
- PoE switch at the house, plus a small outdoor-rated PoE switch at the yard
  end, and one 60–90 ft direct-burial CAT6 run in conduit between them (§5.2)
  — unless there is already power at a rear garage/shed, in which case the
  existing backyard WiFi is adequate and this line drops out.
- An always-on box (§6): used mini PC + Coral, or Pi 5 + AI HAT+. $120–250.
- **Storage: a 500 GB SSD is plenty** under the retention policy in §13
  (~40 GB steady state). Naive continuous recording would have needed ~2.3 TB
  for the same period — the policy, not the disk, is what solves this. Clips
  stay on the box; only crops go to the Mac.
- No IR illuminators — daylight only (§8).
- The MacBook, for training only. No spend.
- Total: roughly $320–650, and none of it needed to start (§6).

No drone spend until M3, and none at all until the software flies in SITL.

### 16.1 Equipment on hand: Nest Cam (indoor, wired, 2nd gen)

**Not usable in the built system**, for two independent reasons.

*It's indoor-rated.* No IP rating, and a 10 ft captive USB cable to a 7.5 W
adapter. It cannot be mounted at the beds.

*It's roughly 5× short on pixel density.* 1080p (1920 px) across a 135°
diagonal FOV works out to ~129° horizontal, so the scene width is ~4.2× the
standoff distance and pixels-per-foot is ~456/d:

| Target | px/ft needed (§5) | Max standoff on this camera |
|---|---|---|
| Chipmunk | ~100 | **4.6 ft** |
| Squirrel | ~50 | 9.1 ft |
| Groundhog | ~25 | 18 ft |

For comparison, the planned 4 MP + 6 mm combination hits 100 px/ft at 25 ft.
A very wide lens on a 2 MP sensor is precisely the purchase §5 warns against —
which is no criticism of the camera, it was built to watch a living room.

*The stream story is also bad.* This generation exposes **no RTSP**. Live
video comes over WebRTC through the Smart Device Management API (Device Access
registration is a one-time US$5, plus OAuth, a GCP project, and Pub/Sub for
events), with sessions that must be periodically extended. The practical route
is Home Assistant's Nest integration re-exposed via go2rtc as RTSP for Frigate.
That works, but it is fragile, and it puts a Google cloud round-trip inside a
pipeline designed to run locally with a sub-second budget.

**What it is genuinely good for: starting this week, for free.**

The key realization is that **M1's real work needs recorded clips, not a live
stream.** Validating that MegaDetector → species classification separates
squirrel from chipmunk on your footage, and fine-tuning on your backgrounds,
are both offline batch jobs on the Mac. So skip the SDM and go2rtc work
entirely — pull clips out of the app and run the pipeline against files.

Siting for that: under a covered porch or eave, or a rear garage overhang if
one has power, within 10 ft of an outlet. Aim it at **one** close bed at 5–9 ft
rather than trying to cover the yard — at that range it has enough pixels on a
squirrel to be a real test. From the house it necessarily looks west into the
afternoon sun (§5.1), so keep the sky out of frame and expect the late-day
frames to be poor; that is itself a useful preview of what §5.1 is protecting
against.

Note: without a Nest Aware subscription, wired cameras retain roughly 3 hours
of event history, so collect the same day or subscribe for a month while
building the dataset.

### 16.2 Camera shortlist

Three buying rules first, because they eliminate most of the catalog:

**1. Motorized varifocal is worth the premium.** You do not yet know the final
mounting points, the bed positions, or the standoff distances, and §5 shows
the framing has to be tight. A manual varifocal means a ladder, a refocus, and
re-sealing the housing every time you adjust — so you won't adjust, and you
will live with bad framing forever. Zoom and focus from a browser is the
difference between iterating and settling.

**2. Ignore the entire night-vision spec sheet.** Daylight-only (§8) makes IR
range, color night vision, starlight sensitivity, and f/1.0 apertures
irrelevant — and that is most of what camera marketing sells. Put the money
into lens range and sensor size instead.

**3. Insist on true/native WDR, not "DWDR."** Digital WDR is tone mapping and
does nothing for a west-facing yard with long shadows and dappled tree shade
(§5.1). A physically larger sensor (1/1.8" rather than 1/2.7") does more for
real dynamic range than any WDR number on the box.

For Frigate specifically, stream reliability ranks **Dahua/EmpireTech >
Amcrest > Reolink**. Dahua substreams are configurable and stable, which
matters directly: Frigate runs detection on the substream.

| Option | Spec | ~Price | Why / why not |
|---|---|---|---|
| **EmpireTech (Dahua) IPC-T5442T-ZE** — *first choice* | 4 MP, 1/1.8" sensor, 2.7–12 mm motorized varifocal, IP67 | $105–135 | Big sensor, full motorized zoom+focus, the clean Dahua substream. Its zoom range spans ~106° to ~33° HFOV, which covers standoffs from ~10 ft out past 40 ft at ≥100 px/ft — the whole range §5 needs, adjustable from a browser. |
| Dahua IPC-HFW2831T-ZAS-S2 | 8 MP, 1/1.8", 3.7–11 mm motorized varifocal, true WDR, IP67 | $170–190 | More pixels, narrower zoom ratio. Worth it if a bed ends up further out than expected. |
| Amcrest IP8M-2496EB | 4 K fixed, 103° FOV, IP67 | $110–125 | Dahua OEM. Reported stable on RTSP for weeks. Too wide for species ID — good as the context camera below. |
| Reolink RLC-810A | 4 K fixed 4 mm, IP66, onboard animal detection | $80–90 | Budget pick, and the known-good exception in a Reolink 4K line that otherwise has Frigate substream problems. 8 MP offsets the wide lens: ~100 px/ft at 20 ft. Onboard animal detection is a useful free motion gate. Fixed lens means you must get the mount right first time. |
| Axis M-series | pro-grade optics and WDR | $400–700 | Genuinely excellent and genuinely unnecessary here. |

**Fleet composition: two tight species cameras plus one wide context camera.**
The wide one cannot do species ID — too few px/ft — but it shows *approach
corridors*: which fence line, which tree, whose yard they come from. That maps
directly onto where deterrents go in M2, and it costs $80.

**Buy one camera first.** Mount it, run it a week, and check the px/ft and
framing assumptions in §5 against reality before buying the other two. The
alternative is owning three of the wrong camera.

Prices and model availability drift; verify current listings before ordering.
EmpireTech is the US-market Dahua channel, and how you get genuine Dahua
firmware stateside.

## 17. Open questions

Site-specific ones are in §4.3. Still open and affecting the build: the time
budget. Language and deploy choices are now recorded as defaults in
[TECH_STACK.md](TECH_STACK.md) — Python end to end, Compose on the always-on
box — rather than left open; easy to revisit, since the MQTT contract is the
only thing they'd have to honor.

Also open and now explicitly drone-gating: **tree canopy** (§4.3, §10.7) and
the site frame/monument decision that all calibration depends on (§10.4).

Resolved: tap-to-launch posture (§3), ground-effector-first (§14), M1 scope
(§14), daylight-only (§8), compute topology (§6),
never-target list (§9), backyard WiFi present (§5.2), target designation via
stereo-with-surface-fallback and terminal visual servo (§10).
