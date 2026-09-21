# Tech stack

Versions current as of **2026-09-21**.

**Verified** column: ✓ = checked against release data while writing this;
~ = from general knowledge, confirm before you pin it.

Language choice is Python end to end. The CV half has no realistic
alternative, and a single language across `classifier`, `brain`, and
`effectors` removes a serialization boundary and a toolchain. The labeler is
FastAPI + HTMX specifically to avoid introducing a JS build for one internal
page. *(This was an open question in PLAN.md §13; recorded here as a default,
not a constraint — say the word and the `brain`/`effectors` services could be
Go or TypeScript without touching the MQTT contract.)*

## Version policy

1. **Pin exact.** `uv.lock` for Python, image **digests** not tags in Compose.
   The always-on box runs unattended for weeks; a silent `:latest` pull that
   breaks detection is indistinguishable from "no critters this week."
2. **Read Frigate release notes before every bump.** 0.17 shipped breaking
   config changes with partial auto-migration. This is the component most
   likely to bite on upgrade.
3. **arm64 wheel availability is the real constraint** if the always-on box is
   a Pi 5 rather than a mini PC. Check before choosing a Python minor.
4. **Models are artifacts, not dependencies.** `species-clf.onnx` is versioned
   and shipped with the eval metrics it achieved (§9.5), not rebuilt in place.
5. **Fine-tune SpeciesNet, don't replace it.** If step 4 of PLAN.md §8.3 is
   reached, fine-tuning SpeciesNet's head beats training a local model from
   scratch — the 2026 literature is clear on this, and you keep the global
   feature representations learned from 65M images.

## Always-on box

| Component | Version | Verified | Notes |
|---|---|---|---|
| Debian | 13 (trixie) | ~ | Or Raspberry Pi OS (trixie-based) on Pi 5 |
| Docker Engine | 28.x | ~ | |
| Docker Compose | v2.3x | ~ | |
| **Frigate** | **0.18.0** | ✓ | Current stable; 0.17.2 is the last 0.17. Ingest, motion gate, zones, recording, snapshot API |
| go2rtc | 1.9.x | ~ | Bundled inside Frigate; no separate deploy |
| Eclipse Mosquitto | 2.0.x | ~ | MQTT broker |
| SQLite | 3.4x | ~ | WAL mode |
| ntfy | 2.x | ~ | Self-hosted, for action-button push |
| Python | **3.13.x** | ~ | Deliberately one minor behind (§ below) |

**Why 3.13 on the box and not 3.14.** Python 3.14.7 is current stable
(2026-08-05) and 3.15.0rc2 is out, with 3.15 stable due October 2026. Pin
**3.13** on the always-on box for arm64 wheel coverage across the CV stack —
this is the machine that must not break unattended. The Mac can run 3.14
freely; nothing is shared but ONNX artifacts, which are version-agnostic.
Avoid 3.15 until it has shipped and the wheels have caught up.

## Models and inference

| Component | Version | Verified | Notes |
|---|---|---|---|
| **MegaDetector** | **v6** | ✓ | Stage 1 (animal/person/vehicle). MDv6-c = YOLOv9-compact; YOLOv11 and RT-DETR variants also released. Microsoft now recommends v6 as default |
| PytorchWildlife | 1.1.x+ | ~ | The package that serves MegaDetector |
| **SpeciesNet** | current | ✓ | Stage 2. EfficientNetV2-M, 2,498 classes, 65M training images, geofencing by coordinates. **May be sufficient unfine-tuned** — see PLAN.md §8.3 before assuming otherwise |
| **Ultralytics** | **8.4.55** | ✓ | Open-vocab auto-labeling (YOLO-World) and any custom detector work. YOLO26 (Jan 2026) is current SOTA — lighter head, native end-to-end inference, ~43% faster CPU ONNX than YOLO11n |
| ONNX Runtime | 1.2x | ~ | Inference on the box. Note: recent versions dropped NVIDIA GTX 900 support — irrelevant on Coral/Hailo, relevant if you ever add a GPU |
| Coral PyCoral / Hailo runtime | current | ~ | Whichever accelerator you buy (§6) |

## Falcon services

| Component | Version | Verified | Notes |
|---|---|---|---|
| FastAPI | 0.1xx | ~ | `brain` HTTP API, labeler |
| Pydantic | 2.x | ~ | The event contract (PLAN.md §7) is Pydantic models — single source of truth |
| Uvicorn | 0.3x | ~ | ASGI |
| paho-mqtt | 2.x | ~ | All services |
| HTMX | 2.x | ~ | Labeler UI; no JS build step |
| uv | current | ~ | Packaging and lockfile |
| Ruff + mypy | current | ~ | Lint, types |
| APScheduler (or systemd timer) | current | ~ | `falcon-janitor` retention sweeps (PLAN.md §11) |

## Development machine

Apple MacBook Pro 14-inch, 2024 — Silver.

| | |
|---|---|
| Chip | **Apple M4 Max** (binned) |
| CPU | 14-core — 10 performance + 4 efficiency |
| GPU | **32-core** |
| Neural Engine | 16-core |
| Unified memory | **36 GB** |
| Memory bandwidth | **410 GB/s** (the 40-core M4 Max is 546 GB/s) |
| Storage | 1 TB SSD |
| Display | 14.2-inch Liquid Retina XDR |

Three numbers drive decisions elsewhere:

- **36 GB** sets the local VLM ceiling. Qwen3-VL-30B-A3B (4-bit) fits but sits
  at the top of it — see PLAN.md §10.4 for the wired-memory setting and why
  the VLM and a training run must not overlap.
- **410 GB/s**, not 546. Token generation is bandwidth-bound, so expect ~50
  tok/s rather than the ~68 tok/s commonly quoted for "M4 Max." Irrelevant for
  batch work, which is all this project asks of it.
- **1 TB** is ample for datasets (~5 GB at 50k crops) and must not become the
  footage archive. Clips live on the always-on box, which needs its own
  sizing — PLAN.md §13.

## MacBook — training and labeling only

| Component | Version | Verified | Notes |
|---|---|---|---|
| **PyTorch** | **2.14.0** | ✓ | Released 2026-09-02. MPS backend for Apple Silicon |
| MLX | 0.2x | ~ | Optional Apple-native alternative for fine-tuning |
| Python | 3.14.x | ✓ | 3.14.7 stable; free to run ahead of the box |
| Label Studio | 1.x | ~ | Only if the HTMX labeler proves insufficient |

## Optional: LLM and embeddings (PLAN.md §10)

Offline and out-of-band only — never in the decision path, never the safety
veto. Nothing here is required for M1.

| Component | Version | Verified | Notes |
|---|---|---|---|
| **mlx-vlm** | current | ✓ | Apple-native VLM inference on the Mac; MLX beats llama.cpp by a wide margin on Apple Silicon |
| **Qwen3-VL-30B-A3B** | 4-bit MLX | ✓ | The local pick at ≥32 GB unified memory. MoE: 30B total, ~3B active, ~68 tok/s on M4 Max |
| Gemma 4 E4B | current | ✓ | Tiny-model fallback for 8–16 GB |
| Ollama | current | ~ | Lower-friction alternative to mlx-vlm |
| DINOv2 / SigLIP | via ONNX Runtime | ~ | Crop embeddings: dataset dedup, similar-event retrieval, novelty detection (§10.3). Runs on the always-on box |
| `anthropic` (Python SDK) | 1.x | ~ | Only if using the cloud path (§10.5). Batch API for 50% off; this workload is fully asynchronous |

Cloud model IDs and rates if that path is taken: `claude-opus-5` ($5/$25 per
MTok) or `claude-haiku-4-5` ($1/$5). Cost is negligible at this volume — see
§10.5 for why privacy, not price, is the thing to weigh.

## Edge firmware (M2)

| Component | Version | Verified | Notes |
|---|---|---|---|
| ESPHome | 2026.x | ~ | ESP32 effector controller |
| Camera firmware | vendor current | — | Update before mounting; ladders are worse than reboots |

## M3 — gated, not deployed

Listed for completeness; nothing here is installed until the PLAN.md §4.2
legal question is answered.

| Component | Version | Verified | Notes |
|---|---|---|---|
| ArduPilot | 4.6/4.7 | ~ | SITL first, hardware later or never |
| MAVSDK-Python | 2.x | ~ | Sortie state machine |
| Gazebo | current LTS | ~ | SITL simulation |

## Checking drift

```bash
# Frigate
curl -s https://api.github.com/repos/blakeblackshear/frigate/releases/latest | jq -r .tag_name
# Python
curl -s https://endoflife.date/api/python.json | jq -r '.[0].latest'
# PyPI packages
for p in ultralytics PytorchWildlife onnxruntime fastapi pydantic; do
  echo "$p $(curl -s https://pypi.org/pypi/$p/json | jq -r .info.version)"
done
```

Anything marked ~ above is worth a pass through this before you commit a
lockfile.
