/// The Settings "Performance ↔ Quality" slider: how much of the screen warp runs (it needs
/// Screen Recording, and macOS shows its recording indicator while it does).
enum RenderQuality: Int, CaseIterable {
    /// No screen capture at all: no recording indicator, no capture cost. The notch's own
    /// liquid effect stays (the Liquid Glass edge stands in for the warp on macOS 26).
    case performance = 0
    /// The warp only while the notch moves (opening, closing, peeking).
    case balanced = 1
    /// Also around the swollen and the open notch, and the lens following the pointer near it.
    case quality = 2

    var title: String {
        switch self {
        case .performance: "Performance"
        case .balanced: "Balanced"
        case .quality: "Quality"
        }
    }

    var summary: String {
        switch self {
        case .performance:
            "No screen warp: nothing is recorded, no recording indicator, the lowest CPU use."
        case .balanced:
            "The screen bends around the notch only while it moves. The recording indicator shows briefly then."
        case .quality:
            "The screen also stays bent around the open notch, and a lens follows the pointer near it. The recording indicator stays on while the panel is open."
        }
    }

    /// Any screen warp at all.
    var warps: Bool { self != .performance }
    /// The warp around the swollen/open notch and the pointer lens.
    var warpsAtRest: Bool { self == .quality }
}
