# PlaneFuse Live demo plan

Do not implement this until the technical performance gate passes.

## 1. User-facing concept

PlaneFuse Live is a fully local Apple-Silicon camera/classification proof. The
current validated workload is MobileNetV2 ImageNet classification rather than
zero-shot semantic retrieval; MobileCLIP remains optional.

Preferred demo:

- camera feed;
- user selects/types concepts such as "keyboard", "coffee mug", "person", "phone";
- local image encoder ranks or recognizes what the camera sees;
- no cloud inference;
- same useful result available through Pipeline B or PlaneFuse C.

If the chosen real model is classification rather than semantic retrieval, adapt the experience to a clear live recognition task without pretending it is semantic search.

Current executable workflow:

```bash
./pf live --sample   # real local M5 corpus B/C inference
./pf live --camera   # actual camera NV12 capture, native-plane resize, B/C inference
```

The camera mode center-crops to an even-aligned square and resizes Y and UV
directly to 224x224 NV12. It reports no inference metrics if camera permission,
assets, or the native frame contract is unavailable.

## 2. Core visual

The app should have two modes or a side-by-side comparison:

```text
OPTIMIZED RGB (B)             PLANEFUSE (C)
NV12 -> RGB -> model          Y+UV -> native stem -> model tail
frontend p50: ...             frontend p50: ...
e2e p50: ...                  e2e p50: ...
p95: ...                      p95: ...
RGB intermediate: yes         RGB intermediate: no
output: ...                   output: ...
```

All live-looking numbers must be real runtime measurements or explicitly labeled stored benchmark results.

## 3. 15-second wow moment

A judge should understand this sequence immediately:

1. The Mac camera produces native YUV/NV12.
2. Normal vision AI expands it into RGB first.
3. PlaneFuse compiles the model's input/stem toward native planes.
4. RGB intermediate disappears.
5. The recognition result remains equivalent.
6. Measured latency/memory/bandwidth improves by the actual verified amount.

## 4. Video outline (target 2:30-2:40)

0:00-0:15 - Hook

"Your camera already gives the computer a compact image representation. Most vision models expand it to RGB just to immediately transform it again. PlaneFuse removes that middle representation."

0:15-0:35 - Show ordinary vs PlaneFuse dataflow.

0:35-1:05 - Live PlaneFuse camera inference and mode switch.

1:05-1:30 - Show measured before/after table and parity.

1:30-1:55 - Explain native-plane stem compilation and 4:2:0 insight visually.

1:55-2:15 - Show developer command workflow and second compatible target if available.

2:15-2:35 - Show profiler/allocation evidence and final headline result.

2:35-2:40 - Close: "Same local vision task. Less representation work. Built for Arm client AI."

## 5. Visual proof assets

Capture:

- A/B/C architecture diagram;
- standard RGB resource/allocation capture;
- PlaneFuse resource/allocation capture;
- benchmark table;
- parity/quality panel;
- clean CLI output;
- app screenshot;
- system/environment summary without personal identifiers.

The current CLI is the reproducible showcase shell. A signed AppKit/SwiftUI
window is intentionally deferred until the camera path has been exercised on a
permitted device; the technical proof remains in the shared core and CLI.

## 6. Do not do

- fake animated counters;
- fabricated power savings;
- huge marketing claims about all vision models;
- long code walkthroughs;
- spend the first minute explaining YUV equations;
- hide Pipeline B;
- show a faster result whose outputs visibly differ.
