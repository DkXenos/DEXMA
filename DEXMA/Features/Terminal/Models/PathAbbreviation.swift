import CoreGraphics

/// How the band shows the shell's working directory: the home directory as `~`, and if it's
/// still too wide, its middle replaced by `…`. Pure (the text measuring is passed in).
nonisolated enum PathAbbreviation {
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, home != "/" else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// `text` if it fits in `maxWidth`, else the longest version with its middle cut out (the
    /// start and the end, which matter most in a path, kept about equally).
    static func fitMiddle(_ text: String, maxWidth: CGFloat, measure: (String) -> CGFloat) -> String {
        guard measure(text) > maxWidth else { return text }
        let characters = Array(text)
        var low = 0, high = characters.count - 1
        var best = "…"
        while low <= high {
            let keep = (low + high) / 2
            let head = (keep + 1) / 2, tail = keep / 2
            let candidate = String(characters.prefix(head)) + "…" + String(characters.suffix(tail))
            if measure(candidate) <= maxWidth {
                best = candidate
                low = keep + 1
            } else {
                high = keep - 1
            }
        }
        return best
    }
}
