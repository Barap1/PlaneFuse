#include <metal_stdlib>
using namespace metal;

// The source weights and offsets are generated from the exact pretrained 3x3
// Conv + BatchNorm parameters. Core ML SAME is bottom/right-heavy here: source
// coordinates are `2 * output + tap`, with only the final row/column padded.
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
            const int x = int(gid.x * 2 + kx);
            const int y = int(gid.y * 2 + ky);
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

// R7.5 C1-SR: spatial-major 4x4 tiles reuse each source Y/UV tap across the
// eight channel residues. The operator, source mapping, and Float32 order are
// unchanged; only the source-read ownership changes.
kernel void nv12ToMobileNetV2StemSourceReuse(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    device float *activation [[buffer(0)]],
    constant float *sourceWeights [[buffer(1)]],
    constant float *sourceOffsets [[buffer(2)]],
    constant float *bias [[buffer(3)]],
    uint3 threadgroupPosition [[threadgroup_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]]) {
    threadgroup uint yTile[9][10];
    threadgroup uint2 uvTile[5][6];

    const uint tileX = threadgroupPosition.x;
    const uint tileY = threadgroupPosition.y;
    const uint sourceOriginX = tileX * 8;
    const uint sourceOriginY = tileY * 8;

    if (tid < 81) {
        const uint localY = tid / 9;
        const uint localX = tid % 9;
        const uint x = sourceOriginX + localX;
        const uint y = sourceOriginY + localY;
        yTile[localY][localX] = (x < 224 && y < 224) ? yPlane.read(uint2(x, y)).x : 0;
    }
    if (tid < 25) {
        const uint localY = tid / 5;
        const uint localX = tid % 5;
        const uint x = tileX * 4 + localX;
        const uint y = tileY * 4 + localY;
        uvTile[localY][localX] = (x < 112 && y < 112) ? uvPlane.read(uint2(x, y)).xy : uint2(0);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const uint localSpatial = tid / 8;
    const uint channelResidue = tid % 8;
    const uint localX = localSpatial % 4;
    const uint localY = localSpatial / 4;
    const uint outputX = tileX * 4 + localX;
    const uint outputY = tileY * 4 + localY;
    if (outputX >= 112 || outputY >= 112) return;

    float values[6];
    for (uint q = 0; q < 6; ++q) values[q] = bias[channelResidue + 8 * q];
    for (uint ky = 0; ky < 3; ++ky) {
        for (uint kx = 0; kx < 3; ++kx) {
            const uint sourceX = localX * 2 + kx;
            const uint sourceY = localY * 2 + ky;
            const uint globalX = sourceOriginX + sourceX;
            const uint globalY = sourceOriginY + sourceY;
            if (globalX >= 224 || globalY >= 224) continue;
            const float luma = (float(yTile[sourceY][sourceX]) - 16.0f) / 219.0f;
            const uint2 chroma = uvTile[sourceY / 2][sourceX / 2];
            const float cb = (float(chroma.x) - 128.0f) / 224.0f;
            const float cr = (float(chroma.y) - 128.0f) / 224.0f;
            const uint tapOffset = ky * 3 + kx;
            for (uint q = 0; q < 6; ++q) {
                const uint channel = channelResidue + 8 * q;
                const uint tap = channel * 9 + tapOffset;
                const uint base = tap * 3;
                values[q] += sourceOffsets[tap] + sourceWeights[base] * luma +
                    sourceWeights[base + 1] * cb + sourceWeights[base + 2] * cr;
            }
        }
    }
    for (uint q = 0; q < 6; ++q) {
        const uint channel = channelResidue + 8 * q;
        activation[(channel * 112 + outputY) * 112 + outputX] = clamp(values[q], 0.0f, 6.0f);
    }
}

// R5 Experiment A: exact nearest-sited 4:2:0 polyphase form. It preserves
// per-tap luma/offset work and aggregates only the repeated chroma phases.
kernel void nv12ToMobileNetV2StemPolyphase(
    texture2d<uint, access::read> yPlane [[texture(0)]],
    texture2d<uint, access::read> uvPlane [[texture(1)]],
    device float *activation [[buffer(0)]],
    constant float *lumaWeights [[buffer(1)]],
    constant float *chromaWeights [[buffer(2)]],
    constant float *sourceOffsets [[buffer(3)]],
    constant float *bias [[buffer(4)]],
    uint3 gid [[thread_position_in_grid]]) {
    if (gid.x >= 112 || gid.y >= 112 || gid.z >= 48) return;
    float value = bias[gid.z];
    for (uint ky = 0; ky < 3; ++ky) {
        for (uint kx = 0; kx < 3; ++kx) {
            const int x = int(gid.x * 2 + kx);
            const int y = int(gid.y * 2 + ky);
            if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
            const float luma = (float(yPlane.read(uint2(x, y)).x) - 16.0f) / 219.0f;
            const uint tap = gid.z * 9 + ky * 3 + kx;
            value += sourceOffsets[tap] + lumaWeights[tap] * luma;
        }
    }
    for (uint chromaY = 0; chromaY < 2; ++chromaY) {
        for (uint chromaX = 0; chromaX < 2; ++chromaX) {
            const int x = int(gid.x * 2 + chromaX * 2);
            const int y = int(gid.y * 2 + chromaY * 2);
            if (x < 0 || x >= 224 || y < 0 || y >= 224) continue;
            const uint2 chroma = uvPlane.read(uint2(x / 2, y / 2)).xy;
            const float cb = (float(chroma.x) - 128.0f) / 224.0f;
            const float cr = (float(chroma.y) - 128.0f) / 224.0f;
            const uint base = (gid.z * 4 + chromaY * 2 + chromaX) * 2;
            value += chromaWeights[base] * cb + chromaWeights[base + 1] * cr;
        }
    }
    activation[(gid.z * 112 + gid.y) * 112 + gid.x] = clamp(value, 0.0f, 6.0f);
}
