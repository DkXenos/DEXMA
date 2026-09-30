import SwiftUI

/// SwiftUI root of the panel. Everything derives from `controller.progress`; nothing here
/// animates on its own.
struct NotchContentView: View {
    let controller: PanelController

    var body: some View {
        let geometry = controller.geometry
        let shape = geometry.shape(at: controller.progress)

        shape
            .fill(.black)
            .ignoresSafeArea()
    }
}
