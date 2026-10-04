import SwiftUI

/// The Devices tab's card content (on the card's black): one card per device, connected first
/// — full width alone, two columns from two devices — or the empty state. Also rendered off
/// screen as the liquid effect's picture of the tab (`DevicesPage`), so it reads everything from
/// the view model and keeps no state of its own.
struct DevicesPageView: View {
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 12

    let viewModel: DevicesViewModel

    var body: some View {
        let devices = viewModel.devices
        Group {
            if devices.isEmpty {
                DevicesEmptyView(bluetoothDenied: viewModel.isBluetoothDenied)
            } else {
                let columns = devices.count > 1 ? 2 : 1
                let rows = stride(from: 0, to: devices.count, by: columns).map { Array(devices[$0..<min($0 + columns, devices.count)]) }
                VStack(spacing: Self.spacing) {
                    ForEach(rows, id: \.first?.id) { row in
                        HStack(alignment: .top, spacing: Self.spacing) {
                            ForEach(row) { device in
                                DeviceCardView(device: device, status: viewModel.status(device),
                                               age: { viewModel.age($0, of: device) })
                                    .frame(maxWidth: .infinity)
                            }
                            if row.count < columns { Color.clear.frame(maxWidth: .infinity, maxHeight: 0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(Self.padding)
        .environment(\.colorScheme, .dark)
    }
}
