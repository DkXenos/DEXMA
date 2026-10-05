import SwiftUI

/// The Devices tab's card content (on the card's black): the devices on the left — a card each,
/// connected first, or the empty card — and the Controls card (brightness, volume) on the
/// right, the two columns as tall as the taller. Also rendered off screen as the liquid
/// effect's picture of the tab (`DevicesPage`), so it reads everything from the view models
/// and keeps no state of its own.
struct DevicesPageView: View {
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12
    /// The Controls column's share of the width (never under 180 pt).
    static let controlsShare: CGFloat = 0.36

    let viewModel: DevicesViewModel
    let controls: QuickControlsViewModel

    var body: some View {
        let devices = viewModel.devices
        GeometryReader { proxy in
            let controlsWidth = max(180, (proxy.size.width - Self.spacing) * Self.controlsShare)
            HStack(alignment: .top, spacing: Self.spacing) {
                VStack(spacing: Self.spacing) {
                    if devices.isEmpty {
                        DevicesEmptyView(bluetoothDenied: viewModel.isBluetoothDenied)
                    } else {
                        ForEach(devices) { device in
                            DeviceCardView(device: device, status: viewModel.status(device),
                                           age: { viewModel.age($0, of: device) })
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                QuickControlsCard(controls: controls)
                    .frame(width: controlsWidth)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.padding)
        .environment(\.colorScheme, .dark)
    }
}
