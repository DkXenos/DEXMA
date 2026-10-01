#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// SwiftUI shaders for the notch's opening/closing motion (see LiquidMotionLayer.swift) and,
// at the end, the band's controls under the pointer. They bend the *content* (terminal,
// Search card, a control's label) and add light; the black silhouette itself is an ordinary
// vector shape underneath, squashed and stretched through its own width and height.
// Coordinates are the panel's, in points, y down; the notch body hangs from y = 0.
// With every effect parameter at 0 both functions are exact identities.

// Signed distance to the notch body (negative inside) and the outward normal. The body is a
// box open at the top (the screen edge) with rounded bottom corners; the small concave ears
// at the top edge are ignored, and every effect fades out there anyway.
// body: centre x, width, height, bottom corner radius.
static float bodyDistance(float2 p, float4 body, thread float2 &normal, thread float2 &q) {
    float cx = body.x, w = body.y, h = body.z, r = body.w;
    float side = p.x < cx ? -1.0 : 1.0;
    q = float2(abs(p.x - cx) - (w * 0.5 - r), p.y - (h - r));
    if (q.x > 0.0 && q.y > 0.0) {  // Around a bottom corner.
        float len = max(length(q), 1e-4);
        normal = float2(side * q.x, q.y) / len;
        return len - r;
    }
    if (q.x > q.y) {  // Nearest to a side.
        normal = float2(side, 0.0);
        return q.x - r;
    }
    normal = float2(0.0, 1.0);  // Nearest to the bottom.
    return q.y - r;
}

// Position along the rim, from the top edge (0) down a side, round the corner and along the
// bottom to the middle (1): where the sweeping highlight is.
static float rimCoordinate(float2 p, float4 body, float2 q) {
    float r = body.w;
    float side = max(body.z - r, 0.0);
    float arc = M_PI_F * 0.5 * r;
    float bottom = max(body.y * 0.5 - r, 0.0);
    float u;
    if (q.y <= 0.0) {
        u = clamp(p.y, 0.0, side);
    } else if (q.x <= 0.0) {
        u = side + arc + min(-q.x, bottom);
    } else {
        u = side + atan2(q.y, q.x) * r;
    }
    return u / max(side + arc + bottom, 1.0);
}

static float gaussian(float x, float width) {
    float k = x / width;
    return exp(-k * k);
}

// Lens rim, chromatic aberration and light, as a layer effect over the terminal snapshot.
// fx: refraction (pt), aberration (pt), highlight opacity, glow opacity.
// light: sweep position (0 top … 1 bottom middle), sweep width, rim width (pt), unused.
[[ stitchable ]] half4 liquidLens(float2 position, SwiftUI::Layer layer,
                                  float4 body, float4 fx, float4 light) {
    float2 normal;
    float2 q;
    float s = bodyDistance(position, body, normal, q);
    float inside = -s;
    float rim = max(min(light.z, 0.4 * min(body.y, body.z)), 1.0);
    // Where the silhouette meets the screen edge there is no rim to bend or light.
    float top = smoothstep(4.0, 20.0, position.y);
    // 1 at the edge, easing to 0 at `rim` inside (and 0 outside: nothing to bend there).
    float edge = inside > 0.0 ? max(1.0 - inside / rim, 0.0) : 0.0;

    // Like looking through the edge of a glass lens: near the rim the content is pulled in
    // from deeper inside. The slope stays below 1, so the mapping never folds over.
    float strength = min(fx.x, 0.45 * rim) * top;
    float2 source = position - normal * (strength * edge * edge);
    float2 split = normal * (fx.y * edge * top);

    half4 color = layer.sample(source);
    if (fx.y > 0.0) {
        half4 red = layer.sample(source + split);
        half4 blue = layer.sample(source - split);
        color = half4(red.r, color.g, blue.b, max(color.a, max(red.a, blue.a)));
    }

    // Light on the glass, drawn over the black silhouette underneath: a white specular line
    // just inside the edge on a soft sheen, brightest where the band sweeps past, its
    // channels fringed a little like the aberration; plus a faint cool glow along the inside.
    float sweep = gaussian(rimCoordinate(position, body, q) - light.x, max(light.y, 0.01));
    float fringe = 0.3 * fx.y;
    float3 spec = float3(gaussian(inside - 1.4 - fringe, 1.3),
                         gaussian(inside - 1.4, 1.3),
                         gaussian(inside - 1.4 + fringe, 1.3))
                + 0.3 * gaussian(inside - 2.5, 5.0);
    float glow = exp(-max(inside, 0.0) / 9.0);
    float coverage = clamp(inside + 0.5, 0.0, 1.0) * top;
    float3 added = (spec * (fx.z * (0.25 + 0.75 * sweep)) + float3(0.88, 0.94, 1.0) * (glow * fx.w)) * coverage;
    color.rgb += half3(added);
    color.a = max(color.a, half(max(added.r, max(added.g, added.b))));
    return color;
}

// Squash & stretch plus anticipation for the content, as a distortion effect: the same
// scale the silhouette gets, anchored at the top centre (the notch hangs from the edge).
// params: centre x, horizontal scale, vertical scale, unused.
[[ stitchable ]] float2 liquidStretch(float2 position, float4 params) {
    return float2(params.x + (position.x - params.x) / params.y, position.y / params.z);
}

// Signed distance to a rounded rectangle (negative inside) and the outward normal.
// rect: x, y, width, height; r: corner radius (height / 2 makes a capsule).
static float roundedRectDistance(float2 p, float4 rect, float r, thread float2 &normal) {
    float2 centre = rect.xy + rect.zw * 0.5;
    float2 d = p - centre;
    float2 q = abs(d) - (rect.zw * 0.5 - r);
    float2 side = float2(d.x < 0.0 ? -1.0 : 1.0, d.y < 0.0 ? -1.0 : 1.0);
    if (q.x > 0.0 && q.y > 0.0) {  // Around a corner.
        float len = max(length(q), 1e-4);
        normal = side * q / len;
        return len - r;
    }
    normal = q.x > q.y ? float2(side.x, 0.0) : float2(0.0, side.y);
    return max(q.x, q.y) - r;
}

// The band's liquid controls (tab segments, Search buttons; see BandControl.swift): the same
// glass as the notch's rim, on a small capsule, plus a magnifier and a glint that follow the
// pointer. Applied to the control padded by a transparent margin, so the bulge and the light
// can spill just past its edge; every sample stays within `margin` of its pixel (the effect's
// maxSampleOffset). With every parameter at 0 it is an exact identity.
// control: x, y, width, height of the control inside the margin.
// lens: pointer x, y, lens radius, magnification at its centre.
// fx: rim refraction (pt), aberration (pt), light opacity, bulge (fraction).
// extra: margin (pt), corner radius (pt; 0 = a capsule), unused × 2.
[[ stitchable ]] half4 liquidControlLens(float2 position, SwiftUI::Layer layer,
                                         float4 control, float4 lens, float4 fx, float4 extra) {
    float2 centre = control.xy + control.zw * 0.5;
    float radius = extra.y > 0.0 ? min(extra.y, control.w * 0.5) : control.w * 0.5;
    // Bulge: the control swells about its centre, so content comes from nearer the centre.
    float2 p = centre + (position - centre) / (1.0 + fx.w);
    // Magnifier around the pointer: strongest at its centre, easing to nothing at its radius.
    float2 toLens = p - lens.xy;
    float k = saturate(1.0 - dot(toLens, toLens) / max(lens.z * lens.z, 1.0));
    p -= toLens * (lens.w * k * k);

    // Rim: as through the edge of a glass lens, content near the (swollen) edge is pulled in.
    float2 normal;
    float inside = -roundedRectDistance(centre + (position - centre) / (1.0 + fx.w), control, radius, normal)
                 * (1.0 + fx.w);
    float edge = inside > 0.0 ? max(1.0 - inside / max(radius, 1.0), 0.0) : 0.0;
    float2 source = p - normal * (fx.x * edge * edge);
    float2 split = normal * (fx.y * edge);
    // Never further than the margin (maxSampleOffset) from this pixel.
    float reach = max(extra.x - 0.5, 0.0);
    float2 offset = source - position;
    float len = length(offset) + length(split);
    if (len > reach) {
        float scale = reach / len;
        offset *= scale;
        split *= scale;
    }
    source = position + offset;

    half4 color = layer.sample(source);
    if (fx.y > 0.0) {
        half4 red = layer.sample(source + split);
        half4 blue = layer.sample(source - split);
        color = half4(red.r, color.g, blue.b, max(color.a, max(red.a, blue.a)));
    }

    // Light on the glass, inside the control only: a soft glint around the pointer and a thin
    // specular line along the rim, brightest near the pointer.
    float2 toPointer = position - lens.xy;
    float near = exp(-length(toPointer) / max(lens.z, 1.0));
    float glint = exp(-dot(toPointer, toPointer) / max(0.25 * lens.z * lens.z, 1.0));
    float rimLine = gaussian(inside - 1.0, 0.9) * (0.35 + 0.65 * near);
    float coverage = clamp(inside + 0.5, 0.0, 1.0);
    float light = (0.45 * glint + rimLine) * fx.z * coverage;
    color.rgb += half3(light * float3(0.94, 0.97, 1.0));
    color.a = max(color.a, half(light));
    return color;
}
