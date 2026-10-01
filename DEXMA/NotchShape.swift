import SwiftUI

/// The notch silhouette: a body hanging from the top edge of the screen with rounded bottom
/// corners, and concave "ears" where it meets the edge so it reads as part of the bezel.
struct NotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var bottomRadius: CGFloat
    var earRadius: CGFloat
    /// Horizontal center of the body within the drawing rect (not animated).
    var centerX: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(bottomRadius, earRadius)) }
        set {
            width = newValue.first.first
            height = newValue.first.second
            bottomRadius = newValue.second.first
            earRadius = newValue.second.second
        }
    }

    /// The bottom corner radius `path(in:)` actually draws (clamped to the size).
    var drawnBottomRadius: CGFloat {
        let ear = min(max(0, earRadius), max(0, height) / 2)
        return max(0, min(bottomRadius, max(0, width) / 2, max(0, height) - ear))
    }

    /// Scaled about the top centre, for squash & stretch. 1 × 1 returns the shape unchanged.
    func scaled(by scale: CGSize) -> NotchShape {
        guard scale != CGSize(width: 1, height: 1) else { return self }
        return NotchShape(width: width * scale.width, height: height * scale.height,
                          bottomRadius: bottomRadius, earRadius: earRadius, centerX: centerX)
    }

    func path(in rect: CGRect) -> Path {
        let w = max(0, width)
        let h = max(0, height)
        guard w > 0, h > 0 else { return Path() }
        let ear = min(max(0, earRadius), h / 2)
        let radius = min(max(0, bottomRadius), w / 2, h - ear)
        let left = rect.minX + centerX - w / 2
        let right = left + w
        let top = rect.minY
        let bottom = top + h

        var path = Path()
        path.move(to: CGPoint(x: left - ear, y: top))
        // Ears are concave: they start on the screen edge outside the body and curve
        // inward, so the silhouette flares into the top edge instead of meeting it at 90°.
        path.addQuadCurve(to: CGPoint(x: left, y: top + ear), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: right - radius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom - radius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top + ear))
        path.addQuadCurve(to: CGPoint(x: right + ear, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }
}
