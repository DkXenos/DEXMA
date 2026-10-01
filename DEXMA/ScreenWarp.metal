#include <metal_stdlib>
using namespace metal;

// Redraws the screen under the panel (a ScreenCaptureKit frame of exactly the panel's rect,
// DEXMA's own windows excluded) bent around the notch, like the screen around the iPhone's
// Camera Control. Drawn below the black silhouette, in panel points (top-left origin).
// Wherever the bend is under half a point the output is transparent, so the real screen shows
// and the warp fades into it without a seam.

struct WarpUniforms {
    float2 size;     // Panel size, points.
    float scale;     // Pixels per point.
    float amount;    // Displacement at the silhouette's edge, points: + pushes outward, − pulls in.
    float4 body;     // Silhouette: centre x, width, height, bottom corner radius.
    float4 pointer;  // Pointer lens: x, y, magnification (0…0.4), radius.
    float reach;     // How far from the edge the bend reaches, points.
    float chroma;    // RGB split, as a fraction of the displacement.
    float2 debug;    // x = 1: cover everything with zero bend (colour-match check).
};

struct WarpVertex {
    float4 position [[position]];
};

vertex WarpVertex warpVertex(uint id [[vertex_id]]) {
    // One triangle covering the whole drawable.
    float2 corner = float2((id << 1) & 2, id & 2);
    WarpVertex out;
    out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    return out;
}

// Signed distance to the notch body (negative inside) and its outward normal; same body as
// LiquidEffects.metal: a box hanging from y = 0 with rounded bottom corners.
static float warpBodyDistance(float2 p, float4 body, thread float2 &normal) {
    float cx = body.x, w = body.y, h = body.z, r = body.w;
    float side = p.x < cx ? -1.0 : 1.0;
    float2 q = float2(abs(p.x - cx) - (w * 0.5 - r), p.y - (h - r));
    if (q.x > 0.0 && q.y > 0.0) {
        float len = max(length(q), 1e-4);
        normal = float2(side * q.x, q.y) / len;
        return len - r;
    }
    if (q.x > q.y) {
        normal = float2(side, 0.0);
        return q.x - r;
    }
    normal = float2(0.0, 1.0);
    return q.y - r;
}

fragment half4 warpFragment(WarpVertex in [[stage_in]],
                            texture2d<half> screen [[texture(0)]],
                            constant WarpUniforms &u [[buffer(0)]]) {
    constexpr sampler bilinear(filter::linear, address::clamp_to_edge);
    float2 p = in.position.xy / u.scale;

    // Around the silhouette: strongest at its edge, easing to nothing `reach` away. Pushing
    // out samples nearer the notch (space flows out of it); pulling in samples further away.
    // Under the silhouette it's hidden by the black anyway. Slopes stay below 1: no fold.
    float2 normal;
    float s = warpBodyDistance(p, u.body, normal);
    float t = clamp(1.0 - max(s, 0.0) / max(u.reach, 1.0), 0.0, 1.0);
    float2 bend = normal * (u.amount * t * t);

    // Around the pointer: a magnifying lens, proportional to the distance from its centre
    // (so it never folds), fading out at its radius.
    float2 fromPointer = p - u.pointer.xy;
    float tp = u.pointer.w > 0.0 ? clamp(1.0 - length(fromPointer) / u.pointer.w, 0.0, 1.0) : 0.0;
    bend += fromPointer * (u.pointer.z * tp * tp);

    // Back to nothing at the window's left, right and bottom edges, so it meets the real
    // screen there too (the top edge is the screen's edge).
    float edge = min(min(p.x, u.size.x - p.x), u.size.y - p.y);
    bend *= smoothstep(0.0, 14.0, edge);

    float strength = length(bend);
    half coverage = u.debug.x > 0.5 ? 1.0h : half(smoothstep(0.0, 0.5, strength));
    if (coverage <= 0.0h) {
        return half4(0.0h);
    }
    float2 toUV = 1.0 / u.size;
    float2 source = p - bend;
    // Colour warp: red bends a little further than green, blue a little less.
    half red = screen.sample(bilinear, (source - bend * u.chroma) * toUV).r;
    half4 green = screen.sample(bilinear, source * toUV);
    half blue = screen.sample(bilinear, (source + bend * u.chroma) * toUV).b;
    return half4(half3(red, green.g, blue) * coverage, coverage);
}
