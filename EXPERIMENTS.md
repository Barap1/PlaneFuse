# PlaneFuse experiment log

Keep this concise and append only experiments that teach something useful.

## E001 - fair native stem versus optimized RGB stem

Date: 2026-08-09
Base commit: 06f1c8350a8c93fbbb1f5449a2ac9ed02160e020
Evidence/observation: B materializes a 4,915,200-byte RGBA32Float intermediate; C reports zero RGB intermediate bytes and uses the same four-feature output contract.
Hypothesis: Folding decode, normalization, and the first linear stem into direct Y/UV projection will reduce end-to-end frontend-plus-stem work even if the isolated fused kernel is not faster than RGB conversion alone.
Change: Added interleaved preallocated B/C timing with one B sequence and one C sequence per iteration, then exposed quick and 100-iteration confirmation workflows.
Correctness: PASS; max feature absolute difference 1.4305115e-6 in both confirmation batches, threshold 1e-5.
Quick benchmark: Three 30-iteration batches measured C p50 0.2057/0.2220/0.2185 ms versus B 0.4361/0.5163/0.4621 ms; e2e delta 52.7-57.0%.
Confirmation benchmark: Two 100-iteration batches measured e2e delta 51.55% and 50.93%; C isolated frontend was 0.74-1.03% slower.
Outcome: ACCEPT
Lesson: The defensible win is end-to-end elimination of the full RGB plus normal-stem path, not a standalone YUV conversion-kernel speedup.
Accepted commit: 06f1c83

Template:

## Exxx - short title

Date:
Base commit:
Evidence/observation:
Hypothesis:
Change:
Correctness:
Quick benchmark:
Confirmation benchmark:
Outcome: ACCEPT / REJECT / INCONCLUSIVE
Lesson:
Accepted commit (if any):
