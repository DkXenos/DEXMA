import Foundation
import Testing
@testable import DEXMA

struct SearchQueryTests {
    @Test func wordsBecomeAGoogleSearch() throws {
        let target = try #require(SearchQuery.target(for: "  how tall is the notch? "))
        #expect(target.url.absoluteString == "https://www.google.com/search?q=how%20tall%20is%20the%20notch?")
        #expect(target.fallback == nil)
        #expect(SearchQuery.target(for: "   ") == nil)
    }

    @Test func addressesOpenDirectly() throws {
        let full = try #require(SearchQuery.target(for: "https://developer.apple.com/documentation"))
        #expect(full.url.absoluteString == "https://developer.apple.com/documentation")
        #expect(full.fallback == nil)

        let bare = try #require(SearchQuery.target(for: "en.wikipedia.org/wiki/Notch"))
        #expect(bare.url.absoluteString == "https://en.wikipedia.org/wiki/Notch")
        #expect(bare.fallback == SearchQuery.googleSearch("en.wikipedia.org/wiki/Notch"))

        #expect(SearchQuery.target(for: "localhost:3000")?.url.absoluteString == "http://localhost:3000")
        #expect(SearchQuery.target(for: "192.168.1.1")?.url.absoluteString == "http://192.168.1.1")
    }

    @Test func thingsThatOnlyLookLikeAddressesFallBackToASearch() throws {
        // A dotted word is tried as an address first, with the search as the way out.
        let dotted = try #require(SearchQuery.target(for: "node.js"))
        #expect(dotted.url.absoluteString == "https://node.js")
        #expect(dotted.fallback == SearchQuery.googleSearch("node.js"))
        // Numbers, spaces and odd characters are never addresses.
        for text in ["3.14", "2+2=4", "swift.ui tutorial", "a..b", "x.y2"] {
            #expect(SearchQuery.target(for: text)?.url.host == "www.google.com", "\(text)")
        }
    }

    @Test func fieldShowsSearchWordsOrTheAddress() {
        let search = SearchQuery.googleSearch("liquid glass")!
        #expect(SearchQuery.displayText(for: search) == "liquid glass")
        let page = URL(string: "https://www.apple.com/macbook-pro/")!
        #expect(SearchQuery.displayText(for: page) == "https://www.apple.com/macbook-pro/")
    }
}
