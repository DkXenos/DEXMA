import AppKit
import os

/// Whether the space showing on a display is a full-screen app (or Split View). There's no
/// public API for another app's full screen (`currentSystemPresentationOptions` reports only
/// DEXMA's own), so this asks the window server's managed-spaces list (type 4 = full screen),
/// looked up once with `dlsym` (CGS/SkyLight, as window managers do). Missing → never full
/// screen, so nothing is ever blocked by mistake. One call: well under a millisecond.
enum FullScreenSpace {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias CopySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let logger = Logger(category: "FullScreen")
    private static let functions: (ConnectionFunction, CopySpacesFunction)? = {
        let handle = dlopen(nil, RTLD_NOW)
        guard let connection = dlsym(handle, "CGSMainConnectionID") ?? dlsym(handle, "SLSMainConnectionID"),
              let copy = dlsym(handle, "CGSCopyManagedDisplaySpaces") ?? dlsym(handle, "SLSCopyManagedDisplaySpaces") else {
            logger.notice("Managed spaces unavailable: full-screen check off")
            return nil
        }
        return (unsafeBitCast(connection, to: ConnectionFunction.self), unsafeBitCast(copy, to: CopySpacesFunction.self))
    }()

    /// The display whose frame (global AppKit coordinates) is `screenFrame` shows a full-screen app.
    static func isActive(onScreenWithFrame screenFrame: CGRect) -> Bool {
        guard let (connection, copySpaces) = functions,
              let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }),
              let displayID = screen.displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let identifier = CFUUIDCreateString(nil, uuid) as String?,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return false }
        // With "Displays have separate Spaces" off there's one entry, "Main", for all of them.
        let display = displays.first { ($0["Display Identifier"] as? String) == identifier }
            ?? (displays.count == 1 ? displays.first : nil)
        let current = display?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == 4
    }
}
