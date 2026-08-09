#include <metal_stdlib>
using namespace metal;

// Pipeline B intentionally materializes the complete normalized RGB input.
kernel void nv12ToMobileNetV2NormalizedRGBA(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    texture2d<float, access::write> normalizedRGBA [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= normalizedRGBA.get_width() || gid.y >= normalizedRGBA.get_height()) return;
    const float y = (float(yPlane.read(gid).x) - 16.0f) / 219.0f;
    const uint2 uv = uvPlane.read(gid / 2).xy;
    const float cb = (float(uv.x) - 128.0f) / 224.0f;
    const float cr = (float(uv.y) - 128.0f) / 224.0f;
    const float3 rgb = float3(y + 1.402f * cr, y - 0.344136f * cb - 0.714136f * cr, y + 1.772f * cb);
    normalizedRGBA.write(float4((rgb - 0.5f) / 0.5f, 1.0f), gid);
}

kernel void mobileNetV2RGBStem(
    texture2d<float, access::read> normalizedRGBA [[texture(0)]],
    device float *activation [[buffer(0)]],
    constant float *weights [[buffer(1)]],
    constant float *bias [[buffer(2)]],
    uint3 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 112 || gid.y >= 112 || gid.z >= 48) return;
    float value = bias[gid.z];
    for (uint ky = 0; ky < 3; ++ky) for (uint kx = 0; kx < 3; ++kx) {
        const int x = int(gid.x * 2 + kx) - 1;
        const int y = int(gid.y * 2 + ky) - 1;
        if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
        const float3 rgb = normalizedRGBA.read(uint2(x, y)).xyz;
        const uint tap = ky * 3 + kx;
        value += weights[(gid.z * 3) * 9 + tap] * rgb.x;
        value += weights[(gid.z * 3 + 1) * 9 + tap] * rgb.y;
        value += weights[(gid.z * 3 + 2) * 9 + tap] * rgb.z;
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}
