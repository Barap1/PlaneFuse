# R7 source-lineage procedural diagnostic

Status: QUALIFIED DIAGNOSTIC; not a B2/C1 quality failure

`proof/r7-source-lineage-release.json` compares the original Apple image-input model with the derived FullArray path over the 64-input R7 corpus. It records top-1 agreement 1.0, real-image top-5 set agreement 1.0, and procedural top-5 set agreement 0.84375. The procedural probability differences are larger than the direct B2/C1 differences and must remain visible.

An inexpensive controlled comparison was possible without changing the model or the final path: the 28 shared `stress-*` samples in the earlier R0 lineage artifact were evaluated with the original image-input adapter configured for CPU-only execution, while the R7 release lineage artifact was generated after the source adapter default changed to `MLComputeUnits.all`; the derived FullArray adapter remained CPU-only in both paths. The deterministic render/preprocessing description and source model hash are the same.

Corpus-level observed metrics:

| source execution | procedural top-5 set agreement | probability max error |
| --- | ---: | ---: |
| R0 source CPU-only vs FullArray CPU-only | 1.000000 | `8.344650268554688e-7` corpus max |
| R7 source `.all` vs FullArray CPU-only | 0.843750 | `0.014868199825286865` corpus max |

On the exact 28 shared procedural IDs, R0 has 28/28 top-5 set matches and R7 has 23/28; the five R7 shared mismatches are retained. The R0/R7 artifact comparison shows that backend/precision execution is a strong explanation for the procedural divergence: the only intentional lineage execution-policy change is the original source model's CPU-only versus `.all` selection, and the divergence appears on procedural near-tie cases while all 32 real-image top-5 sets still agree. This is evidence-backed attribution, not a universal proof that no preprocessing/backend interaction contributes.

The diagnostic commands were:

```text
git show 0a32f857:Sources/PlaneFuseCore/MobileNetV2Integration.swift  # source adapter used .cpuOnly
git show 578a96c:Sources/PlaneFuseCore/MobileNetV2Integration.swift  # source adapter defaulted to .all
python3 -B scripts/check_r7_source_lineage_diagnostic.py
```

Qualification for review: retain all 32 procedural cases and their lower source-lineage top-5 agreement. Do not transfer this diagnostic to the matched B2/C1 quality claim; B2/C1 quality is separately measured over the output-blind corpus in `proof/r7-b2-c1-shared-quality-clean.json`.
