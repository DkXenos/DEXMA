import Observation

/// The fingers on the trackpad right now, for `TrackpadPreview`. Fed only while the Settings
/// window is open.
@Observable
final class TrackpadPreviewViewModel {
    var touches: [TouchPoint] = []
}
