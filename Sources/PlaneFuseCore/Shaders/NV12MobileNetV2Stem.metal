#include <metal_stdlib>
using namespace metal;

// The source weights and offsets are generated from the exact pretrained 3x3
// Conv + BatchNorm parameters. Offsets are per tap so SAME zero padding does
// not accidentally add RGB preprocessing bias outside the source image.
kernel void nv12ToMobileNetV2Stem(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    device float *activation [[buffer(0)]],
    constant float *sourceWeights [[buffer(1)]],
    constant float *sourceOffsets [[buffer(2)]],
    constant float *bias [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 112 || gid.y >= 112 || gid.z >= 48) return;
    float value = bias[gid.z];
    for (uint ky = 0; ky < 3; ++ky) {
        for (uint kx = 0; kx < 3; ++kx) {
            const int x = int(gid.x * 2 + kx) - 1;
            const int y = int(gid.y * 2 + ky) - 1;
            if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
            const float luma = (float(yPlane.read(uint2(x, y)).x) - 16.0f) / 219.0f;
            const uint2 chroma = uvPlane.read(uint2(x / 2, y / 2)).xy;
            const float cb = (float(chroma.x) - 128.0f) / 224.0f;
            const float cr = (float(chroma.y) - 128.0f) / 224.0f;
            const uint tap = gid.z * 9 + ky * 3 + kx;
            const uint base = tap * 3;
            value += sourceOffsets[tap] + sourceWeights[base] * luma +
                sourceWeights[base + 1] * cb + sourceWeights[base + 2] * cr;
        }
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}
