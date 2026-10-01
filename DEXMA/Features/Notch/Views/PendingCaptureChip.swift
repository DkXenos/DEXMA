import SwiftUI

/// A capture waiting for claude.ai's message box: its thumbnail (20 pt tall, radius 6) and a ✕
/// to discard it. Faded while it waits by itself; with an orange edge once it needs a click to
/// try again.
struct PendingCaptureChip: View {
    let pending: PendingCapture
    let band: BandMotion
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        let waiting = pending.state == .waiting
        let size = CGSize(width: CaptureBandLayout.chipWidth(aspect: pending.image.aspect),
                          height: CaptureBandLayout.chipHeight)
        let shape = RoundedRectangle(cornerRadius: CaptureBandLayout.chipRadius, style: .continuous)
        HStack(spacing: 2) {
            Button(action: retry) {
                Image(decorative: pending.image.thumbnail, scale: 3)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(waiting ? .white.opacity(0.25) : .orange.opacity(0.85), lineWidth: 1))
                    .opacity(waiting ? 0.7 : 1)
            }
            .buttonStyle(BandButtonStyle(lens: band.lens(for: "capture.chip"), size: size,
                                         cornerRadius: CaptureBandLayout.chipRadius))
            .help(waiting ? "Waiting for claude.ai: goes into the message box as soon as it's ready"
                          : "Click to put it in Claude's message box")
            Button(action: discard) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(BandButtonStyle(lens: band.lens(for: "capture.discard"), size: CaptureBandLayout.discardSize,
                                         cornerRadius: 5))
            .help("Discard capture")
        }
    }
}
