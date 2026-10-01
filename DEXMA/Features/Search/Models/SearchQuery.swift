import Foundation

/// What the Search field's text means: a web address to open as it is, or words to search on
/// Google. Pure, so it's unit-tested.
nonisolated enum SearchQuery {
    /// Where to go for `text` (nil when blank). `fallback`: a Google search to load instead if
    /// `url` was only guessed to be an address and its host can't be found ("node.js").
    struct Target: Equatable {
        let url: URL
        let fallback: URL?
    }

    static func target(for text: String) -> Target? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let search = googleSearch(trimmed) else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return Target(url: url, fallback: nil)
        }
        if let host = hostName(trimmed) {
            // Local servers rarely speak HTTPS.
            let scheme = host == "localhost" || host.allSatisfy({ $0.isNumber || $0 == "." }) ? "http" : "https"
            if let url = URL(string: "\(scheme)://\(trimmed)"), url.host != nil {
                return Target(url: url, fallback: search)
            }
        }
        return Target(url: search, fallback: nil)
    }

    static func googleSearch(_ words: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [URLQueryItem(name: "q", value: words)]
        return components.url
    }

    /// What the field shows for a loaded page: the words of a Google search, else the address.
    static func displayText(for url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let host = components.host, host == "google.com" || host.hasSuffix(".google.com"),
           components.path == "/search",
           let words = components.queryItems?.first(where: { $0.name == "q" })?.value, !words.isEmpty {
            return words
        }
        return url.absoluteString
    }

    /// The host if `text` reads like an address without a scheme ("apple.com",
    /// "en.wikipedia.org/wiki/Notch", "localhost:3000", "192.168.1.1"), else nil.
    private static func hostName(_ text: String) -> String? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let authority = text.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let host = String(authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first ?? "").lowercased()
        if host == "localhost" { return host }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }), let last = labels.last else { return nil }
        if labels.count == 4, labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return host }
        let validLabels = labels.allSatisfy { $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
        return validLabels && last.count >= 2 && last.allSatisfy(\.isLetter) ? host : nil
    }
}
