import CoreGraphics

/// Where a finished capture flies to: into the notch (it shrinks into a drop and vanishes into
/// the hardware notch), or into the floating glass field's chip (it shrinks onto the chip,
/// which shows the same picture).
nonisolated enum CaptureLandingStyle: Equatable {
    case notch
    case chip(cornerRadius: CGFloat)
}
