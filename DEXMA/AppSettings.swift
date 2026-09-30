import AppKit
import Carbon.HIToolbox
import Observation

/// A global shortcut as Carbon wants it, plus how to show it.
nonisolated struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String
    /// For showing the shortcut next to a menu item ("" if it has no character).
    var menuKey: String

    static let defaultCombo = KeyCombo(keyCode: UInt32(kVK_ANSI_Grave),
                                       carbonModifiers: UInt32(optionKey), display: "⌥`",
                                       menuKey: "`")

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }
}

enum DisplayChoice: String, CaseIterable {
    /// The built-in display's notch (or the primary screen when the lid is closed).
    case notched
    /// Whichever screen the pointer is on when the panel opens.
    case pointer
}

/// User preferences, persisted in UserDefaults. `onChange` fires after every edit.
@Observable
final class AppSettings {
    static let panelWidthRange = 480.0...1100.0
    static let panelHeightRange = 260.0...720.0
    static let edgeZoneRange = 0.05...0.30
    static let triggerDistanceRange = 0.15...0.60
    static let durationRange = 0.25...0.80
    static let bounceRange = 0.0...0.40
    static let effectIntensityRange = 0.0...1.0

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var hotKey: KeyCombo {
        didSet { save(try? JSONEncoder().encode(hotKey), "hotKey") }
    }
    var panelWidth: Double { didSet { save(panelWidth, "panelWidth") } }
    var panelHeight: Double { didSet { save(panelHeight, "panelHeight") } }
    var gesturesEnabled: Bool { didSet { save(gesturesEnabled, "gesturesEnabled") } }
    /// Top fraction of the trackpad where an open-swipe must start.
    var edgeZone: Double { didSet { save(edgeZone, "edgeZone") } }
    /// Fraction of the trackpad height that equals a full open.
    var triggerDistance: Double { didSet { save(triggerDistance, "triggerDistance") } }
    var invertTrackpadY: Bool { didSet { save(invertTrackpadY, "invertTrackpadY") } }
    var animationDuration: Double { didSet { save(animationDuration, "animationDuration") } }
    var bounce: Double { didSet { save(bounce, "bounce") } }
    /// Liquid lens effect while opening/closing: 0 = off … 1 = full (`EffectTuning.full`).
    var effectIntensity: Double { didSet { save(effectIntensity, "effectIntensity") } }
    var escClosesPanel: Bool { didSet { save(escClosesPanel, "escClosesPanel") } }
    var closesOnFocusLoss: Bool { didSet { save(closesOnFocusLoss, "closesOnFocusLoss") } }
    var hoverToPeek: Bool { didSet { save(hoverToPeek, "hoverToPeek") } }
    var display: DisplayChoice { didSet { save(display.rawValue, "display") } }

    init() {
        let d = UserDefaults.standard
        func double(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard d.object(forKey: key) != nil else { return fallback }
            return min(max(d.double(forKey: key), range.lowerBound), range.upperBound)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        hotKey = d.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            ?? .defaultCombo
        panelWidth = double("panelWidth", 680, Self.panelWidthRange)
        panelHeight = double("panelHeight", 400, Self.panelHeightRange)
        gesturesEnabled = bool("gesturesEnabled", true)
        edgeZone = double("edgeZone", 0.12, Self.edgeZoneRange)
        triggerDistance = double("triggerDistance", 0.30, Self.triggerDistanceRange)
        invertTrackpadY = bool("invertTrackpadY", false)
        animationDuration = double("animationDuration", 0.45, Self.durationRange)
        bounce = double("bounce", 0.20, Self.bounceRange)
        effectIntensity = double("effectIntensity", 1, Self.effectIntensityRange)
        escClosesPanel = bool("escClosesPanel", true)
        closesOnFocusLoss = bool("closesOnFocusLoss", true)
        hoverToPeek = bool("hoverToPeek", true)
        display = d.string(forKey: "display").flatMap(DisplayChoice.init(rawValue:)) ?? .notched
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
