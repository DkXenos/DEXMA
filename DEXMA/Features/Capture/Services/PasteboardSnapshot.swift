import AppKit

/// Everything on the general pasteboard, copied out, so a capture can borrow the clipboard for
/// a real paste and put the user's contents back right after.
struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ board: NSPasteboard = .general) {
        items = board.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        } ?? []
    }

    func restore(to board: NSPasteboard = .general) {
        board.clearContents()
        if !items.isEmpty { board.writeObjects(items) }
    }
}
