#include <metal_stdlib>
using namespace metal;

struct CameraResizeParameters {
    uint cropOriginX;
    uint cropOriginY;
    uint cropSide;
};

kernel void cameraResizeY(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<uint, access::write> destination [[texture(1)]],
    constant CameraResizeParameters &parameters [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= 224 || gid.y >= 224) return;
    const uint x = parameters.cropOriginX + gid.x * parameters.cropSide / 224;
    const uint y = parameters.cropOriginY + gid.y * parameters.cropSide / 224;
    const float value = source.read(uint2(x, y)).r;
    destination.write(uint4(uint(value * 255.0f + 0.5f), 0, 0, 0), gid);
}

kernel void cameraResizeUV(
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<uint, access::write> destination [[texture(1)]],
    constant CameraResizeParameters &parameters [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= 112 || gid.y >= 112) return;
    const uint x = parameters.cropOriginX / 2 + gid.x * (parameters.cropSide / 2) / 112;
    const uint y = parameters.cropOriginY / 2 + gid.y * (parameters.cropSide / 2) / 112;
    const float2 value = source.read(uint2(x, y)).rg;
    destination.write(uint4(
        uint(value.x * 255.0f + 0.5f), uint(value.y * 255.0f + 0.5f), 0, 0
    ), gid);
}
