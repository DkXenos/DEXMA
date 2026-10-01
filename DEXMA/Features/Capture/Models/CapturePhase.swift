/// Where a capture is: nothing going on, the screen being frozen, the user drawing, the
/// selection settling (morph and lift), or the picture flying into the notch.
enum CapturePhase: Equatable {
    case idle
    case freezing
    case drawing
    case selecting
    case flying
}
