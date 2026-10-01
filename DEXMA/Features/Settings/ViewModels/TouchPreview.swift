import Observation

/// Latest trackpad contacts, fed only while the Settings window is open.
@Observable
final class TouchPreview {
    var touches: [TouchPoint] = []
}
