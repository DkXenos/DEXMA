/// What the panel is doing. Where it is on screen is `NotchViewModel.progress`.
enum PanelState {
    case closed
    /// Pointer hovering the notch: swollen slightly, a click opens.
    case peek
    case open
}
