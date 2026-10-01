import SwiftUI

/// The Screen Recording sheet for Draw to ask, in DEXMA's look: true black, white type.
struct CaptureOnboardingView: View {
    let viewModel: CaptureOnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draw to ask Claude").font(.system(size: 17, weight: .semibold))
                    Text("Circle anything on screen, then ask about it.")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Text("""
                To see what you draw around, DEXMA needs Screen Recording. It takes one still \
                picture of the display when capture starts, with DEXMA's own windows left out, and \
                keeps only the part you select, in memory, until it's in Claude's message box. \
                Nothing is recorded or saved unless you turn on saving in Settings.
                """)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            status
            HStack {
                Button("Not Now") { viewModel.dismiss?() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                action
            }
        }
        .padding(22)
        .frame(width: 400)
        .foregroundStyle(.white)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 8) {
            switch viewModel.status {
            case .needsPermission:
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text("Turn on DEXMA under Screen & System Audio Recording.")
            case .checking:
                ProgressView().controlSize(.small)
                Text("Allowed. Checking…")
            case .needsRelaunch:
                Image(systemName: "arrow.clockwise.circle").foregroundStyle(.orange)
                Text("Allowed. macOS wants DEXMA reopened before it can capture.")
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("All set. Next time, press \(viewModel.shortcut) or the pencil in the notch.")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
    }

    @ViewBuilder private var action: some View {
        switch viewModel.status {
        case .needsPermission, .checking:
            Button("Open System Settings…", action: viewModel.openSystemSettings)
                .keyboardShortcut(.defaultAction)
        case .needsRelaunch:
            Button("Relaunch DEXMA", action: viewModel.relaunch)
                .keyboardShortcut(.defaultAction)
        case .ready:
            Button("Draw Now", action: viewModel.drawNow)
                .keyboardShortcut(.defaultAction)
        }
    }
}
