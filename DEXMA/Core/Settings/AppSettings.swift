import Foundation
import Observation

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
    static let claudeZoomRange = 0.5...1.5

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
    /// How much of the screen warp runs (Performance / Balanced / Quality). Replaces the old
    /// on/off "screenWarp" switch (on → Quality, off → Performance).
    var renderQuality: RenderQuality { didSet { save(renderQuality.rawValue, "renderQuality") } }
    /// The Claude tab's page zoom (1 = 100 %): lower fits more in the panel.
    var claudeZoom: Double { didSet { save(claudeZoom, "claudeZoom") } }
    var escClosesPanel: Bool { didSet { save(escClosesPanel, "escClosesPanel") } }
    var closesOnFocusLoss: Bool { didSet { save(closesOnFocusLoss, "closesOnFocusLoss") } }
    var hoverToPeek: Bool { didSet { save(hoverToPeek, "hoverToPeek") } }
    var display: DisplayChoice { didSet { save(display.rawValue, "display") } }
    /// Draw to ask: its own global shortcut.
    var captureHotKey: KeyCombo {
        didSet { save(try? JSONEncoder().encode(captureHotKey), "captureHotKey") }
    }
    /// Each capture goes into a new Claude chat (otherwise the one that's open).
    var captureNewChat: Bool { didSet { save(captureNewChat, "captureNewChat") } }
    /// Also keep a copy of each capture in ~/Pictures/DEXMA.
    var captureSavesCopies: Bool { didSet { save(captureSavesCopies, "captureSavesCopies") } }
    /// Capture mode's edge glow and stroke shimmer follow the glass effect strength…
    var captureEffectsFollowGlass: Bool { didSet { save(captureEffectsFollowGlass, "captureEffectsFollowGlass") } }
    /// …or this, 0 = off … 1 = full.
    var captureEffectIntensity: Double { didSet { save(captureEffectIntensity, "captureEffectIntensity") } }

    /// The capture effects' strength in use.
    var captureEffectiveIntensity: Double {
        captureEffectsFollowGlass ? effectIntensity : captureEffectIntensity
    }

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
        if d.object(forKey: "renderQuality") != nil {
            renderQuality = RenderQuality(rawValue: d.integer(forKey: "renderQuality")) ?? .quality
        } else {
            renderQuality = bool("screenWarp", true) ? .quality : .performance
        }
        claudeZoom = double("claudeZoom", 1, Self.claudeZoomRange)
        escClosesPanel = bool("escClosesPanel", true)
        closesOnFocusLoss = bool("closesOnFocusLoss", true)
        hoverToPeek = bool("hoverToPeek", true)
        display = d.string(forKey: "display").flatMap(DisplayChoice.init(rawValue:)) ?? .notched
        captureHotKey = d.data(forKey: "captureHotKey").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
            ?? .defaultCaptureCombo
        captureNewChat = bool("captureNewChat", false)
        captureSavesCopies = bool("captureSavesCopies", false)
        captureEffectsFollowGlass = bool("captureEffectsFollowGlass", true)
        captureEffectIntensity = double("captureEffectIntensity", 1, Self.effectIntensityRange)
    }

    private func save(_ value: Any?, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }
}
