#include <metal_stdlib>
using namespace metal;

// Pipeline B intentionally materializes the complete normalized RGB input.
kernel void nv12ToMobileNetV2NormalizedRGBA(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    texture2d<float, access::write> normalizedRGBA [[texture(2)]],
    constant float *color [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= normalizedRGBA.get_width() || gid.y >= normalizedRGBA.get_height()) return;
    const float y = (float(yPlane.read(gid).x) - color[0]) / color[1];
    const uint2 uv = uvPlane.read(gid / 2).xy;
    const float cb = (float(uv.x) - color[2]) / color[3];
    const float cr = (float(uv.y) - color[2]) / color[3];
    const float3 rgb = float3(
        y * color[4] + cb * color[5] + cr * color[6],
        y * color[8] + cb * color[9] + cr * color[10],
        y * color[12] + cb * color[13] + cr * color[14]
    );
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
        // Core ML SAME placement is bottom/right-heavy for this 224/3/2 stem.
        const int x = int(gid.x * 2 + kx);
        const int y = int(gid.y * 2 + ky);
        if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
        const float3 rgb = normalizedRGBA.read(uint2(x, y)).xyz;
        const uint tap = ky * 3 + kx;
        value += weights[(gid.z * 3) * 9 + tap] * rgb.x;
        value += weights[(gid.z * 3 + 1) * 9 + tap] * rgb.y;
        value += weights[(gid.z * 3 + 2) * 9 + tap] * rgb.z;
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}

kernel void nv12ToMobileNetV2NormalizedRGBCHW(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    device float *normalizedRGB [[buffer(0)]],
    constant float *color [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= 224 || gid.y >= 224) return;
    const float y = (float(yPlane.read(gid).x) - color[0]) / color[1];
    const uint2 uv = uvPlane.read(gid / 2).xy;
    const float cb = (float(uv.x) - color[2]) / color[3];
    const float cr = (float(uv.y) - color[2]) / color[3];
    const float3 rgb = (float3(
        y * color[4] + cb * color[5] + cr * color[6],
        y * color[8] + cb * color[9] + cr * color[10],
        y * color[12] + cb * color[13] + cr * color[14]
    ) - 0.5f) / 0.5f;
    const uint pixel = gid.y * 224 + gid.x;
    normalizedRGB[pixel] = rgb.x;
    normalizedRGB[224 * 224 + pixel] = rgb.y;
    normalizedRGB[2 * 224 * 224 + pixel] = rgb.z;
}

kernel void mobileNetV2RGBCHWStem(
    device const float *normalizedRGB [[buffer(0)]],
    device float *activation [[buffer(1)]],
    constant float *weights [[buffer(2)]],
    constant float *bias [[buffer(3)]],
    uint3 gid [[thread_position_in_grid]]) {
    if (gid.x >= 112 || gid.y >= 112 || gid.z >= 48) return;
    float value = bias[gid.z];
    const uint pixels = 224 * 224;
    for (uint ky = 0; ky < 3; ++ky) for (uint kx = 0; kx < 3; ++kx) {
        const int x = int(gid.x * 2 + kx);
        const int y = int(gid.y * 2 + ky);
        if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
        const uint pixel = uint(y * 224 + x);
        const uint tap = ky * 3 + kx;
        value += weights[(gid.z * 3) * 9 + tap] * normalizedRGB[pixel];
        value += weights[(gid.z * 3 + 1) * 9 + tap] * normalizedRGB[pixels + pixel];
        value += weights[(gid.z * 3 + 2) * 9 + tap] * normalizedRGB[2 * pixels + pixel];
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}
