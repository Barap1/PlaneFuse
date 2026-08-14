# PlaneFuse MobileNetV2 integration example

This example uses the public `PlaneFuseCore` runtime API after an application
has converted one camera frame to the verified 224×224 NV12 texture contract.
The live target already implements the camera-side crop/resize bridge in
`Sources/PlaneFuseLive/CameraNV12MetalBridge.swift`.

The runtime creates the Metal stem and Core ML tail once, then reuses the
persistent activation storage for every frame. It does not allocate a full RGB
intermediate.

The same snippet is kept as a compile-checked source file in
[`README.swift`](README.swift):

```swift
let adapter = try MobileNetV2CameraAdapter(device: device, root: projectRoot)
let label = try adapter.classify(resizedNV12: frame)
```

The complete camera sequence is:

1. Receive `AVCaptureVideoDataOutput`'s `CVPixelBuffer` and read its YCbCr
   matrix/range attachments.
2. Use a reusable `CVMetalTextureCache` to map the Y and UV planes. The
   application bridge center-crops/resizes them into `r8Uint` and `rg8Uint`
   224×224 textures.
3. Pass those textures to `PlaneFuseMobileNetV2Runtime.predict`.
4. Reuse the runtime for the next frame and consume the returned local
   classification.

This is the verified MobileNetV2 integration boundary, not a generic Core ML
graph compiler. Run the example's type-check during repository validation with:

```bash
./scripts/check_integration_example.sh
```
