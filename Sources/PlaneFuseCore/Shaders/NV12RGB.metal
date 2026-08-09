#include <metal_stdlib>

using namespace metal;

// Pipeline B deliberately expands NV12 into a complete normalized RGBA model-input
// intermediate. Pipeline C must not reuse this kernel because it avoids that texture.
kernel void nv12ToNormalizedRGBA(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    texture2d<float, access::write> normalizedRGBA [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= normalizedRGBA.get_width() || gid.y >= normalizedRGBA.get_height()) {
        return;
    }

    const float y = (float(yPlane.read(gid).x) - 16.0f) / 219.0f;
    const uint2 uv = uvPlane.read(gid / 2).xy;
    const float cb = (float(uv.x) - 128.0f) / 224.0f;
    const float cr = (float(uv.y) - 128.0f) / 224.0f;

    const float3 rgb = float3(
        y + 1.4020000000000000f * cr,
        y - 0.3441360000000000f * cb - 0.7141360000000000f * cr,
        y + 1.7720000000000000f * cb
    );
    const float3 normalized = (rgb - float3(0.485f, 0.456f, 0.406f)) /
        float3(0.229f, 0.224f, 0.225f);

    normalizedRGBA.write(float4(normalized, 1.0f), gid);
}
