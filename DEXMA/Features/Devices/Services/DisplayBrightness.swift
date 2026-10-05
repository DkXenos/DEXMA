import AppKit
import os

/// The built-in display's brightness. There's no public API for it on Apple silicon (IOKit's
/// display parameters don't apply), so this uses the DisplayServices framework that the
/// system's brightness keys go through, looked up once with `dlsym` (as MonitorControl and
/// Lunar do): Get/Set/CanChangeBrightness(displayID). External displays need DDC: not here.
enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias CanChangeFunction = @convention(c) (CGDirectDisplayID) -> Bool

    private static let logger = Logger(category: "Controls")
    private static let functions: (GetFunction, SetFunction, CanChangeFunction)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let get = dlsym(handle, "DisplayServicesGetBrightness"),
              let set = dlsym(handle, "DisplayServicesSetBrightness"),
              let can = dlsym(handle, "DisplayServicesCanChangeBrightness") else {
            logger.notice("DisplayServices unavailable: no brightness slider")
            return nil
        }
        return (unsafeBitCast(get, to: GetFunction.self), unsafeBitCast(set, to: SetFunction.self),
                unsafeBitCast(can, to: CanChangeFunction.self))
    }()

    private static var builtInDisplay: CGDirectDisplayID? {
        NSScreen.screens.compactMap(\.displayID).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// 0…1, or nil (no built-in display, e.g. lid closed, or it can't be changed).
    static func level() -> Float? {
        guard let (get, _, canChange) = functions, let display = builtInDisplay, canChange(display) else { return nil }
        var value: Float = 0
        return get(display, &value) == 0 ? value : nil
    }

    static func set(_ value: Float) {
        guard let (_, set, canChange) = functions, let display = builtInDisplay, canChange(display) else { return }
        // 0 is allowed, as with the brightness keys (the user's choice, 2026-10-05).
        _ = set(display, min(max(value, 0), 1))
    }
}
