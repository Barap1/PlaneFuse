#include <metal_stdlib>

using namespace metal;

// Pipeline C: direct source-plane projection. The coefficient buffer stores four
// float4 rows (xyz are decoded Y/Cb/Cr weights) followed by a float4 bias. No RGB
// or normalization intermediate is materialized by this kernel.
kernel void nv12ToNativeStemFeatures(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    texture2d<float, access::write> features [[texture(2)]],
    constant float4 *coefficients [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= features.get_width() || gid.y >= features.get_height()) {
        return;
    }

    const float y = (float(yPlane.read(gid).x) - 16.0f) / 219.0f;
    const uint2 uv = uvPlane.read(gid / 2).xy;
    const float cb = (float(uv.x) - 128.0f) / 224.0f;
    const float cr = (float(uv.y) - 128.0f) / 224.0f;
    const float3 source = float3(y, cb, cr);
    const float4 bias = coefficients[4];

    features.write(float4(
        dot(coefficients[0].xyz, source) + bias.x,
        dot(coefficients[1].xyz, source) + bias.y,
        dot(coefficients[2].xyz, source) + bias.z,
        dot(coefficients[3].xyz, source) + bias.w
    ), gid);
}
