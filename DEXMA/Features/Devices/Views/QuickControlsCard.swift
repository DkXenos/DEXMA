import SwiftUI

/// The Devices tab's Controls: the built-in display's brightness and the output volume, each a
/// label with its percentage over a `LevelSlider`. Same card look as a device's.
struct QuickControlsCard: View {
    let controls: QuickControlsViewModel
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 14) {
            row("Display", level: controls.brightness, symbol: controls.brightnessSymbol,
                enabled: controls.brightness != nil, set: controls.setBrightness)
            row("Sound", level: controls.volume.map { _ in controls.shownVolume }, symbol: controls.volumeSymbol,
                enabled: controls.canSetVolume, set: controls.setVolume)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(shape.fill(.white.opacity(0.06)))
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 1 / max(displayScale, 1)))
    }

    private func row(_ title: String, level: Double?, symbol: String, enabled: Bool,
                     set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                Text(level.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.55))
            LevelSlider(value: level ?? 0, symbol: symbol, isEnabled: enabled && level != nil, onChange: set)
        }
    }
}
