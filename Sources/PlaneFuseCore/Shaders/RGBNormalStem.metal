#include <metal_stdlib>

using namespace metal;

// Pipeline B's normal learned 1x1 RGB stem. This consumes the full normalized
// RGBA intermediate already materialized by NV12RGB; it does not decode source
// planes, normalize, or perform any color conversion.
//
// The coefficient buffer contains four float4 rows with RGB weights followed by
// one float4 row containing the four output biases.
kernel void normalizedRGBToStemFeatures(
    texture2d<float, access::read> normalizedRGBA [[texture(0)]],
    texture2d<float, access::write> features [[texture(1)]],
    constant float4 *coefficients [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= features.get_width() || gid.y >= features.get_height()) {
        return;
    }

    const float3 normalizedRGB = normalizedRGBA.read(gid).xyz;
    const float4 bias = coefficients[4];

    features.write(float4(
        dot(coefficients[0].xyz, normalizedRGB) + bias.x,
        dot(coefficients[1].xyz, normalizedRGB) + bias.y,
        dot(coefficients[2].xyz, normalizedRGB) + bias.z,
        dot(coefficients[3].xyz, normalizedRGB) + bias.w
    ), gid);
}
