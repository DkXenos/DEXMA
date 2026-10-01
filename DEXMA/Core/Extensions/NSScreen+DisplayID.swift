import AppKit

extension NSScreen {
    /// The Quartz display ID, which ScreenCaptureKit identifies displays by.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
