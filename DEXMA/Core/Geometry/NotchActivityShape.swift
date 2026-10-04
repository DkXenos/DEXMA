import CoreGraphics

/// A Dynamic-Island-style pill grown out of the closed notch (the Devices connect peek):
/// `size` once fully out; `amount` 0 (just the notch) … 1 (out), overshooting with its spring.
nonisolated struct NotchActivityShape: Equatable {
    var size: CGSize
    var amount: CGFloat
}
