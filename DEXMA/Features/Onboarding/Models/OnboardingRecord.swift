import Foundation

/// Whether the user has seen the welcome window: closed it with Done or its close button.
/// Quitting with it open doesn't count, so it comes back on the next launch.
nonisolated enum OnboardingRecord {
    private static let key = "didShowOnboarding"

    static var isSeen: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
