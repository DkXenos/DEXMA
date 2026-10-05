import Foundation
import Observation

/// The Devices tab's Controls card: the built-in display's brightness and the output volume.
/// Volume follows the system live (`SystemVolume`'s listeners); brightness has no change
/// notification, so it's re-read whenever the tab comes to rest on screen (`refresh`).
@Observable
final class QuickControlsViewModel {
    /// 0…1; nil when unavailable.
    private(set) var brightness: Double?
    private(set) var volume: Double?
    private(set) var isMuted = false
    private(set) var canSetVolume = false

    @ObservationIgnored private let output: SystemVolume

    init(output: SystemVolume) {
        self.output = output
        output.onChange = { [weak self] in self?.readVolume() }
        output.start()
        readVolume()
        readBrightness()
    }

    var brightnessSymbol: String {
        (brightness ?? 1) < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }

    var volumeSymbol: String {
        guard let volume, !isMuted, volume > 0 else { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    /// Shown on the slider: muted reads as 0.
    var shownVolume: Double {
        isMuted ? 0 : volume ?? 0
    }

    func setBrightness(_ value: Double) {
        guard brightness != nil else { return }
        let level = max(value, Double(DisplayBrightness.minimum))
        DisplayBrightness.set(Float(level))
        if brightness != level { brightness = level }
    }

    func setVolume(_ value: Double) {
        output.set(volume: Float(value))
        readVolume()
    }

    /// The tab is on screen: catch up with changes made elsewhere (brightness keys).
    func refresh() {
        readBrightness()
        readVolume()
    }

    private func readBrightness() {
        let level = DisplayBrightness.level().map(Double.init)
        // Ignore float noise from the round trip so the page isn't re-rendered for nothing.
        if let level, let brightness, abs(level - brightness) < 0.001 { return }
        if level != brightness { brightness = level }
    }

    private func readVolume() {
        let level = output.volume.map(Double.init)
        if level != volume { volume = level }
        if output.isMuted != isMuted { isMuted = output.isMuted }
        if output.isSettable != canSetVolume { canSetVolume = output.isSettable }
    }
}
