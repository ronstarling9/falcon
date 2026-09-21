# falcon — working agreements

A vision system that watches a garden, identifies the animal, and escalates to
a deterrent. Planning stage: **no code exists yet.**

## KISS — keep it simple, stupid

The simplest thing that could work, built first, measured, and only then
made less simple — with the measurement as the reason.

- **One camera, one model, one notification** is a complete M1. Everything
  else in `docs/PLAN.md` is a later decision, not a starting requirement.
- **Prefer a file to a database, a cron to a daemon, a directory to a UI,
  and a function to a service.** Reach for the heavier thing when the
  lighter one has actually failed, and say in the commit what failed.
- **Don't build what Frigate already does.** Ingest, motion gating, zones,
  recording, snapshots and retention are solved. Our code is the classifier
  sidecar and the policy on top.
- **No abstraction without two real implementations.** The `Effector`
  interface earns its keep because notify and sprinkler both exist. Nothing
  else has cleared that bar.
- If a design needs a diagram to be understood, prefer the design that
  doesn't.

## YAGNI — you aren't gonna need it

Build for the milestone in front of you. Not the one after it.

- **No speculative generality.** No plugin systems, no config for one
  caller, no interfaces with one implementation, no schema fields nothing
  reads yet.
- **Delete rather than comment out.** Git remembers.
- Every "we might later want…" belongs in `docs/PLAN.md` as prose, never in
  the codebase as scaffolding.
- **Measure before optimizing, and before buying.** Motion gating means the
  model sees ~1% of frames — try CPU inference before buying an accelerator.
- A known list of things this plan describes but should *not* be built yet
  is in **PLAN.md §0**. Check it before adding anything from the later
  sections.

## Where complexity is actually justified

Two places, and only these. Both are safety, not engineering taste:

1. **The protected-class veto** (§9). Dogs, cats, children, birds. Asymmetric
   error costs justify asymmetric machinery: vetoes, trailing windows,
   shadow mode, deliberate negative farming. Do not simplify this away.
2. **Anything that can move or hurt.** Geofence floors, break-off rules,
   sortie budgets, abort paths (§11). These are cheap to write and
   catastrophic to omit.

Everywhere else, argue for less.

## Doc discipline

`docs/` is ahead of the code and should stop growing until code catches up.

- The plan records **decisions and the reasoning behind them** — not every
  option considered. When a question resolves, replace the options with the
  answer.
- Prefer editing an existing section to adding a new one.
- Don't add a doc that restates another doc.
- A cross-reference must resolve. Renumbering sections means fixing every
  `§n` in `docs/` and `README.md`.

## Conventions

- Python end to end; Docker Compose on the always-on box. See
  `docs/TECH_STACK.md`.
- Regenerate diagrams with `tools/render-diagrams.sh` and commit the renders
  alongside `docs/deployment.puml`.
- Daylight-only detection; night is out of scope.
- Drone work (M3) is gated on the §4.2 legal question. SITL first, hardware
  last.
