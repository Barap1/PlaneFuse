#include <metal_stdlib>
using namespace metal;

struct CameraSpaceParameters {
    uint cropOriginX;
    uint cropOriginY;
    uint cropSide;
};

// Conventional B still materializes full planar normalized RGB. This only
// composes camera-space nearest sampling with the accepted B2 conversion.
kernel void cameraSpaceNV12ToMobileNetV2NormalizedRGBCHW(
    texture2d<float, access::read> yPlane [[texture(0)]],
    texture2d<float, access::read> uvPlane [[texture(1)]],
    device float *normalizedRGB [[buffer(0)]],
    constant CameraSpaceParameters &parameters [[buffer(1)]],
    constant float *color [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 224 || gid.y >= 224) return;
    const uint sourceX = parameters.cropOriginX + gid.x * parameters.cropSide / 224;
    const uint sourceY = parameters.cropOriginY + gid.y * parameters.cropSide / 224;
    const uint uvX = parameters.cropOriginX / 2 + ((gid.x / 2) * (parameters.cropSide / 2)) / 112;
    const uint uvY = parameters.cropOriginY / 2 + ((gid.y / 2) * (parameters.cropSide / 2)) / 112;
    const uint yCode = uint(yPlane.read(uint2(sourceX, sourceY)).r * 255.0f + 0.5f);
    const float2 uvValue = uvPlane.read(uint2(uvX, uvY)).rg;
    const uint cbCode = uint(uvValue.x * 255.0f + 0.5f);
    const uint crCode = uint(uvValue.y * 255.0f + 0.5f);
    const float y = (float(yCode) - color[0]) / color[1];
    const float cb = (float(cbCode) - color[2]) / color[3];
    const float cr = (float(crCode) - color[2]) / color[3];
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
