# M7 reusability proof

Status: accepted configuration-layer gate

PlaneFuse now exposes a common `NativePlaneStemSpec` and
`NativePlaneStemInspection` contract. The contract validates the narrow family
that the implemented native kernel can defend today:

- 224x224 input to 112x112 output;
- 3x3, stride-2 Conv2D with SAME bottom/right coordinates;
- 8-bit bi-planar NV12 Y+UV input;
- RGB CHW affine normalization;
- optional BatchNorm folding and ReLU6;
- explicit coefficient and model lineage.

Two distinct configurations pass through the same validator:

1. Apple MobileNetV2 ImageNet, with the real 48-channel pretrained stem and
   source-derived coefficient lineage.
2. A 16-channel parameterized reference fixture, deliberately labeled as
   non-pretrained. It proves the reusable geometry/normalization contract is
   not hard-coded to MobileNetV2's channel count without making a false claim
   that a second pretrained model was integrated.

This is a configuration and inspection proof, not a second performance claim.
The next milestone exposes it through `planefuse inspect`, `compile`, `verify`,
and `bench`, with unsupported graph semantics rejected explicitly. A second
real pretrained model remains optional; MobileCLIP must not displace the
validated MobileNetV2 evidence.

Validation:

```text
swift test --filter NativePlaneCompilerTests
```
