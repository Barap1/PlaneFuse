# What we tried

PlaneFuse developed through a sequence of bounded implementation experiments.
The useful result came from measuring the schedule around the representation
boundary, not from assuming that fewer tensors always means lower latency.

| Attempt | Result | What we learned |
| --- | --- | --- |
| Analytic native-plane stem | Correct on the fixture and model path | The affine transform can be compiled into a compatible first stem without retraining. |
| Shared activation bridge | Accepted comparison boundary | A persistent Float32 activation and unchanged Core ML tail make B2 and C1 comparable. |
| Float16 experiment | Rejected on the declared quality gate | Lower precision was not a free optimization for this workload. |
| Metal 4 feasibility | Not usable on the stable toolchain and model format | The release path must use the stable Metal/Core ML toolchain. |
| Polyphase compiler | Mathematically correct, no stable end-to-end win | Fewer generated operations did not translate into a reliable application result. |
| Direct camera-space fusion | Slower in R6.5 | Removing a resized source representation also removed spatial and channel reuse. |
| C1-SR source reuse | Accepted R7.5 result | Staging native source tiles and reusing them across channels recovered the useful part of the schedule. |

The final design keeps the representation elimination narrow: full RGB is
removed before the stem, while the activation and model tail remain at the
same boundary. Performance research is frozen at the reviewed C1-SR result.
