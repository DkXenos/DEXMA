import SwiftUI

/// Live view of the fingers on the trackpad, with the start zone shaded — for checking the
/// direction and tuning the zone.
struct TrackpadPreview: View {
    let viewModel: TrackpadPreviewViewModel
    let edgeZone: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Canvas { context, size in
                let pad = CGRect(origin: .zero, size: size)
                context.fill(Path(roundedRect: pad, cornerRadius: 10), with: .color(.secondary.opacity(0.15)))
                let zone = CGRect(x: 0, y: 0, width: size.width, height: size.height * edgeZone)
                context.fill(Path(zone), with: .color(.accentColor.opacity(0.25)))
                for touch in viewModel.touches {
                    // Trackpad y is 1 at the far (top) edge; the canvas grows downward.
                    let center = CGPoint(x: touch.x * size.width, y: (1 - touch.y) * size.height)
                    context.fill(Path(ellipseIn: CGRect(x: center.x - 9, y: center.y - 9, width: 18, height: 18)),
                                 with: .color(.accentColor))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .frame(height: 130)
            Text("Put two fingers in the shaded zone at the top, then swipe down.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
