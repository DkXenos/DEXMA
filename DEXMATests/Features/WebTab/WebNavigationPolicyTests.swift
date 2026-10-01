import Foundation
import Testing
@testable import DEXMA

struct WebNavigationPolicyTests {
    private func url(_ text: String) -> URL { URL(string: text)! }

    @Test func claudeKeepsItsOwnAndSignInPagesAndHandsTheRestToTheBrowser() {
        let policy = WebTabConfiguration.claude.policy
        #expect(policy.decide(url("https://claude.ai/new"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("https://claude.ai/chat/1234"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("https://accounts.google.com/o/oauth2/v2/auth?x=1"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("https://appleid.apple.com/auth"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("https://support.anthropic.com/en/"), isMainFrame: true) == .allow)
        // Citations and other sites: the default browser.
        #expect(policy.decide(url("https://en.wikipedia.org/wiki/Notch"), isMainFrame: true) == .openExternally)
        #expect(policy.decide(url("https://www.google.com/search?q=x"), isMainFrame: true) == .openExternally)
        #expect(policy.decide(url("https://notclaude.ai/"), isMainFrame: true) == .openExternally)
        // Frames inside claude.ai (captchas, sign-in widgets) stay.
        #expect(policy.decide(url("https://challenges.cloudflare.com/x"), isMainFrame: false) == .allow)
        #expect(policy.decide(url("blob:https://claude.ai/123"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("mailto:support@anthropic.com"), isMainFrame: true) == .openExternally)
    }

    @Test func searchKeepsEveryWebPage() {
        let policy = WebTabConfiguration.search.policy
        #expect(policy.decide(url("https://en.wikipedia.org/wiki/Notch"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("http://localhost:3000"), isMainFrame: true) == .allow)
        #expect(policy.decide(url("facetime://someone"), isMainFrame: true) == .openExternally)
    }
}
