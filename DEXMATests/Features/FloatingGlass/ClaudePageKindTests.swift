import Foundation
import Testing
@testable import DEXMA

struct ClaudePageKindTests {
    private func kind(_ string: String?) -> ClaudePageKind {
        ClaudePageKind(url: string.flatMap(URL.init(string:)))
    }

    @Test func newChatStaysAField() {
        #expect(kind("https://claude.ai/new") == .newChat)
        #expect(kind("https://claude.ai/") == .newChat)
        #expect(!kind("https://claude.ai/new").showsPage)
    }

    @Test func conversationOpensTheCard() {
        #expect(kind("https://claude.ai/chat/0f3c2a6e-1111-2222-3333-444455556666") == .conversation)
        #expect(kind("https://claude.ai/chat/abc").showsPage)
    }

    @Test func signingInOpensTheCard() {
        #expect(kind("https://claude.ai/login") == .signIn)
        #expect(kind("https://claude.ai/magic-link#token") == .signIn)
        #expect(kind("https://accounts.google.com/o/oauth2") == .signIn)
        #expect(kind("https://claude.ai/login").showsPage)
    }

    @Test func otherPagesAndNothingLoaded() {
        #expect(kind("https://claude.ai/settings/profile") == .other)
        #expect(kind("https://example.com/") == .other)
        #expect(kind(nil) == .other)
    }
}
