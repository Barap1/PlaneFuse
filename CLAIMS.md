# PlaneFuse public claims ledger

Nothing quantitative may be presented in README, Devpost, screenshots, or video as a fact unless it is recorded here with evidence.

## Claim status values

- PROPOSED - desired claim, not yet proven.
- VERIFIED - backed by committed reproducible evidence.
- REJECTED - measured false or misleading; do not use.
- QUALIFIED - true only under stated conditions.

## C001 - No full RGB intermediate in PlaneFuse Pipeline C

Status: PROPOSED

Claim wording target: "PlaneFuse's native path produces the first model features directly from Y and UV planes without materializing a full RGB intermediate."

Required evidence:

- implementation/dataflow inspection;
- allocation/buffer graph or profiler capture;
- supported format/model scope documented.

Evidence files: TBD

## C002 - PlaneFuse improves frontend latency vs optimized RGB

Status: PROPOSED

Claim wording: TBD from actual measurements.

Required evidence:

- Pipeline B and C same-work benchmark;
- confirmation/final run;
- commit/system metadata;
- correctness pass.

Evidence files: TBD

## C003 - PlaneFuse improves end-to-end inference latency

Status: PROPOSED

Claim wording: TBD.

Required evidence:

- real-model B/C benchmark;
- same model/input/build;
- quality agreement;
- final repeated results.

Evidence files: TBD

## C004 - Model behavior is preserved

Status: PROPOSED

Claim wording: TBD by selected model/task.

Required evidence:

- activation comparison;
- fixed validation corpus;
- task/output agreement report.

Evidence files: TBD

## C005 - Fully local Mobile AI experience

Status: PROPOSED

Claim wording target: "PlaneFuse Live performs the demonstrated vision inference locally on Apple Silicon without a cloud inference dependency."

Required evidence:

- architecture/runtime inspection;
- demo with networking not required for inference;
- setup docs.

Evidence files: TBD
