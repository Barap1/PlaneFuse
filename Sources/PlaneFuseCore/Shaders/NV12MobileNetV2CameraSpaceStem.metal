#include <metal_stdlib>
using namespace metal;

struct CameraSpaceParameters {
    uint cropOriginX;
    uint cropOriginY;
    uint cropSide;
};

// This is the exact accepted resize->C1 composition. Source textures are
// UNorm, so each read is first reconstructed as the byte code emitted by the
// existing camera resize shader before the established source-domain math.
kernel void cameraSpaceNV12ToMobileNetV2Stem(
    texture2d<float, access::read> yPlane [[texture(0)]],
    texture2d<float, access::read> uvPlane [[texture(1)]],
    device float *activation [[buffer(0)]],
    constant float *sourceWeights [[buffer(1)]],
    constant float *sourceOffsets [[buffer(2)]],
    constant float *bias [[buffer(3)]],
    constant CameraSpaceParameters &parameters [[buffer(4)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 112 || gid.y >= 112 || gid.z >= 48) return;
    float value = bias[gid.z];
    for (uint ky = 0; ky < 3; ++ky) {
        for (uint kx = 0; kx < 3; ++kx) {
            const uint rx = gid.x * 2 + kx;
            const uint ry = gid.y * 2 + ky;
            if (rx >= 224 || ry >= 224) continue;
            const uint sourceX = parameters.cropOriginX + rx * parameters.cropSide / 224;
            const uint sourceY = parameters.cropOriginY + ry * parameters.cropSide / 224;
            const uint lumaCode = uint(yPlane.read(uint2(sourceX, sourceY)).r * 255.0f + 0.5f);
            const uint uvX = parameters.cropOriginX / 2 + ((rx / 2) * (parameters.cropSide / 2)) / 112;
            const uint uvY = parameters.cropOriginY / 2 + ((ry / 2) * (parameters.cropSide / 2)) / 112;
            const float2 uvValue = uvPlane.read(uint2(uvX, uvY)).rg;
            const uint cbCode = uint(uvValue.x * 255.0f + 0.5f);
            const uint crCode = uint(uvValue.y * 255.0f + 0.5f);
            const float luma = (float(lumaCode) - 16.0f) / 219.0f;
            const float cb = (float(cbCode) - 128.0f) / 224.0f;
            const float cr = (float(crCode) - 128.0f) / 224.0f;
            const uint tap = gid.z * 9 + ky * 3 + kx;
            const uint base = tap * 3;
            value += sourceOffsets[tap] + sourceWeights[base] * luma +
                sourceWeights[base + 1] * cb + sourceWeights[base + 2] * cr;
        }
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}
