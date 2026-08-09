# M9 PlaneFuse Live proof

Status: implementation accepted; physical camera run is environment-qualified

`planefuse-live --sample` runs the real four-image MobileNetV2 B/C workload and
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

The current development machine's smoke run was blocked before capture by its
camera permission state. That is recorded as an environment limitation, not a
fabricated success; a permitted Apple-Silicon run is required before claiming a
physical camera screenshot or video.

Commands:

```bash
./pf live --help
./pf live --sample
./pf live --camera
```
