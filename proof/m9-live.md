# M9 PlaneFuse Live proof

Status: implementation accepted; R0 physical-camera smoke passed on the local permitted device; continuous capture remains an R6 gate

`planefuse-live --sample` runs the real 32-input MobileNetV2 B/C workload and
prints measured frontend/e2e timing, activation parity, top-1 agreement, and
the C intermediate byte count. The validated sample mode produced 100% task
agreement, `9.298325e-6` maximum B/C activation error, and zero C RGBA32Float
intermediate bytes in the existing M5 runtime.

`planefuse-live --camera` uses `AVCaptureVideoDataOutput` configured for
video-range bi-planar NV12. It captures one actual frame, locks the native
planes with their reported strides, applies an even-aligned center-square crop,
and nearest-resizes Y and interleaved UV directly to the 224x224 input contract.
It then runs one real Pipeline B and Pipeline C stem plus the unchanged Core ML
tail and reports the measured single-frame comparison. The resize adapter does
not reconstruct RGB.

R0 confirmed one permitted physical frame; the measured smoke is recorded in
`proof/r0-camera-smoke.md`. This is not continuous camera throughput or video
evidence, and no fabricated success is reported for those later gates.

Commands:

```bash
./pf live --help
./pf live --sample
./pf live --camera
```
