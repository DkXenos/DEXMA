/// What shows the Devices connect peek: the notch (`NotchViewModel` implements it). The Devices
/// feature decides when; the notch decides whether it can (not while open or capturing) and how.
protocol DeviceActivityTarget: AnyObject {
    /// Grows the notch into the pill for a few seconds. Returns false if it didn't (the panel
    /// is open, a capture is going on, or a full-screen app is in front and `allowedInFullScreen`
    /// is false).
    @discardableResult
    func showDeviceActivity(_ activity: DeviceActivity, allowedInFullScreen: Bool) -> Bool
    /// New levels for a pill that's out (for the same device): just the text changes.
    func updateDeviceActivity(_ activity: DeviceActivity)
}
