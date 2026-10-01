import SwiftUI

/// The right end of the band, on every tab: while a capture waits for claude.ai its chip, then
/// the Capture button (Draw to ask). Laid out by `CaptureBandLayout`; the tab's context gets the
/// rest of the region.
struct CaptureControls: View {
    let capture: CaptureViewModel
    let band: BandMotion
    let region: CGRect
    /// A click on a band control: a tick, then the action (`NotchViewModel.click`).
    let click: (@escaping () -> Void) -> Void

    var body: some View {
        HStack(spacing: CaptureBandLayout.spacing) {
            if let pending = capture.pending {
                PendingCaptureChip(pending: pending, band: band, retry: { click(capture.retryPending) },
                                   discard: { click(capture.discardPending) })
            }
            Button { click(capture.start) } label: {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(BandButtonStyle(lens: band.lens(for: "capture"), size: CaptureBandLayout.buttonSize))
            .help("Draw to ask Claude  \(capture.shortcut)")
        }
        .frame(width: region.width, height: region.height, alignment: .trailing)
        .offset(x: region.minX, y: region.minY)
    }
}
