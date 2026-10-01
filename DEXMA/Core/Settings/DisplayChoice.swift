enum DisplayChoice: String, CaseIterable {
    /// The built-in display's notch (or the primary screen when the lid is closed).
    case notched
    /// Whichever screen the pointer is on when the panel opens.
    case pointer
}
