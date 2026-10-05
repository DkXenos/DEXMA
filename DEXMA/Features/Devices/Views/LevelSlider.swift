import SwiftUI

/// A Control Center-style level slider: a 28 pt capsule, white 12 % track, white fill that
/// grows from a circle holding the icon. Click or drag anywhere on it; the value follows the
/// pointer directly (no animation). Dimmed and inert when unavailable.
struct LevelSlider: View {
    static let height: CGFloat = 28

    let value: Double
    let symbol: String
    let isEnabled: Bool
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let track = SliderTrack(width: proxy.size.width, height: Self.height)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(.white.opacity(isEnabled ? 0.92 : 0.25))
                    .frame(width: track.fillWidth(for: isEnabled ? value : 0))
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(isEnabled ? 0.55 : 0.4))
                    .frame(width: Self.height, height: Self.height)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                onChange(track.value(at: drag.location.x))
            })
        }
        .frame(height: Self.height)
    }
}
