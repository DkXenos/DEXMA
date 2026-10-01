import AppKit
import SwiftTerm

/// The terminal view, reporting whenever the shell prints (output arrives on the main queue).
final class ShellTerminalView: LocalProcessTerminalView {
    var onOutput: (() -> Void)?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onOutput?()
    }
}
