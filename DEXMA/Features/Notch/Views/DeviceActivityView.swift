import SwiftUI

/// The connect peek's content on the pill around the notch: the device's icon in the left wing;
/// in the right one its buds ("L 80% · R 75%") with the case smaller below. A low battery alert
/// turns the icon red; a low level is red either way. Laid out by `ActivityPillLayout` (panel
/// coordinates).
struct DeviceActivityView: View {
    let activity: DeviceActivity
    let layout: ActivityPillLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: activity.symbol)
                .font(.system(size: ActivityPillLayout.iconSize, weight: .semibold))
                .foregroundStyle(activity.isAlert ? DevicesPalette.red : .white)
                .position(layout.iconCenter)
            VStack(spacing: 1) {
                line(activity.mainParts)
                    .font(.system(size: ActivityPillLayout.fontSize, weight: .semibold))
                if let part = activity.casePart {
                    Text(part.text)
                        .font(.system(size: ActivityPillLayout.secondaryFontSize, weight: .medium))
                        .foregroundStyle(part.isLow ? DevicesPalette.red : .white.opacity(0.55))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: layout.textFrame.width, height: layout.textFrame.height)
            .offset(x: layout.textFrame.minX, y: layout.textFrame.minY)
        }
    }

    private func line(_ parts: [DeviceActivity.Part]) -> Text {
        parts.enumerated().reduce(Text("")) { line, item in
            let (index, part) = item
            let separator = index == 0 ? Text("") : Text(DeviceActivity.separator).foregroundStyle(.white.opacity(0.4))
            return line + separator + Text(part.text).foregroundStyle(part.isLow ? DevicesPalette.red : .white)
        }
    }
}
