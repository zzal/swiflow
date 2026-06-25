import Testing
import Swiflow
@testable import SwiflowUI

@Suite("ThemeToken")
struct ThemeTokenTests {
    @Test("Typed statics map to the right --sw-* names")
    func typedStatics() {
        #expect(ThemeToken.accent("#7c3aed") == ThemeToken(name: "--sw-accent", value: "#7c3aed"))
        #expect(ThemeToken.radius("12px").name  == "--sw-radius")
        #expect(ThemeToken.surface("#fff").name == "--sw-surface")
        #expect(ThemeToken.text("#111").name    == "--sw-text")
        #expect(ThemeToken.border("#ccc").name  == "--sw-border")
        #expect(ThemeToken.danger("#dc2626").name  == "--sw-danger")
        #expect(ThemeToken.success("#16a34a").name == "--sw-success")
    }

    @Test(".token is a passthrough escape hatch")
    func tokenEscapeHatch() {
        let t = ThemeToken.token("--sw-space-md", "1rem")
        #expect(t.name == "--sw-space-md")
        #expect(t.value == "1rem")
    }
}
