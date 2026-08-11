# PlaneFuse Live — under-three-minute capture plan

Internal capture plan. Do not upload without human approval.

1. **0:00–0:15 — thesis.** Show the dashboard title and say: “PlaneFuse decides when an RGB representation is worth materializing. Here, the camera remains NV12 through the first learned stem.”
2. **0:15–0:45 — live frame.** Show the real camera preview, top-3 labels/confidence, `LIVE METRICS`, FPS, and drops. Point out the exact `NV12 → stem → shared tail` boundary.
3. **0:45–1:20 — A/B toggle.** Switch B2 RGB and PlaneFuse C1-SR. Point to the RGB intermediate indicator, CPU activation-copy indicator, and parity indicator. Never replace live values with stored values.
4. **1:20–2:05 — stored evidence.** Open the evidence panel and show the R7.5 confirmation: 6.1755% below accepted C1, 11.8128% below fresh B2, activation max 5.960464e-6, and full top-5 agreement. Say “STORED EVIDENCE” aloud.
5. **2:05–2:35 — reuse lesson.** Show the architecture diagram and explain that R6.5 direct camera-space fusion was slower because the removed intermediate had reuse value; C1-SR reuses source tiles instead.
6. **2:35–2:55 — limits.** State that MobileNetV2 is the claimed workload, T2/T3 were not established, the fresh camera attempt may be unavailable, and the repository/video/submission still require approval.

Capture checklist: camera permission granted, no personal machine identifiers in frame, no fabricated values, no unlicensed assets/music, and human approval before external publication.
