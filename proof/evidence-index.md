# Evidence navigation

The current headline is the accepted R7.5 C1-SR result. The page generated at
[`docs/JUDGE_EVIDENCE.md`](../docs/JUDGE_EVIDENCE.md) is the compact judge-first
front door; it reads the authoritative JSON below rather than duplicating
benchmark statistics by hand.

| Question | Authoritative path | Checker |
| --- | --- | --- |
| Fixed 64-input corpus | `proof/m5-validation-corpus.json` | `scripts/check_r7_corpus.py` |
| Repaired B2/C1 performance | `proof/r7-final-b2-c1-shared-repaired-conditions.json` | `scripts/check_r7_repaired_shared_benchmark.py` |
| B2/C1 quality and retained disagreements | `proof/r7-b2-c1-shared-quality-conditions.json` | R7 packet / quality contract |
| R7 profiler events | `proof/r7-final-shared-path-profile-repaired-conditions.json`, `proof/profiler/r7-b2-c1-shared-repaired-events-full.json` | `scripts/check_r7_shared_profiler.py` |
| Historical camera provenance | `proof/r7-camera-evidence.json` | `scripts/check_r7_camera_provenance.py` |
| A/B/C selection | `proof/r7-final-selection-matrix.json` | `scripts/check_r7_final_selection_matrix.py` |
| R7.5 raw + aggregate confirmation | `proof/r7.5-source-reuse-batches/52db138-20260811T1605Z-confirm/`, `proof/r7.5-source-reuse-final-52db138-20260811T1605Z-confirm.json` | `scripts/check_r75_source_reuse.py` |
| R7.5 target evaluation | `proof/r7.5-competition-targets.json` | `scripts/check_r75_source_reuse.py` plus target review |
| Independent review | `proof/reviews/R7-R75-HOSTILE-9DAFDBC-20260811.md` | Review contract |

The old pre-repair and first R7.5 artifacts remain preserved as historical/superseded evidence. They are not silently reused as final results.
