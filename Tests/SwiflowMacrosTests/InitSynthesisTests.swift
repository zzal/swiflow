import Testing
import SwiftSyntax
import SwiftSyntaxMacros
@testable import SwiflowMacrosPlugin

@Suite("Macro/InitSynthesis")
struct InitSynthesisTests {
    private func parseStruct(_ src: String) -> StructDeclSyntax {
        DeclSyntax(stringLiteral: src).as(StructDeclSyntax.self)!
    }

    @Test("Annotated stored properties become init parameters in source order; defaults are copied (the test seam)")
    func annotatedParamsCopyDefaults() {
        let s = parseStruct("""
        struct Q {
            let id: Int
            var api: FakeAPI = FakeAPI()
        }
        """)
        #expect(InitSynthesis.memberwiseInit(for: s, access: "")?.trimmedDescription == """
        init(id: Int, api: FakeAPI = FakeAPI()) {
            self.id = id
            self.api = api
        }
        """)
    }

    @Test("An unannotated dependency keeps its inline default and is omitted from the init (not injectable)")
    func unannotatedOmitted() {
        let s = parseStruct("""
        struct Q {
            let id: Int
            var api = FakeAPI()
        }
        """)
        #expect(InitSynthesis.memberwiseInit(for: s, access: "")?.trimmedDescription == """
        init(id: Int) {
            self.id = id
        }
        """)
    }

    @Test("A public access keyword emits a public init (for public query/mutation types)")
    func publicInit() {
        let s = parseStruct("struct Q { let id: Int }")
        #expect(InitSynthesis.memberwiseInit(for: s, access: "public ")?.trimmedDescription == """
        public init(id: Int) {
            self.id = id
        }
        """)
    }

    @Test("A package access keyword emits a package init (reachable across the package's modules)")
    func packageInit() {
        let s = parseStruct("struct Q { let id: Int }")
        #expect(InitSynthesis.memberwiseInit(for: s, access: "package ")?.trimmedDescription == """
        package init(id: Int) {
            self.id = id
        }
        """)
    }

    @Test("A user-written init suppresses synthesis entirely (returns nil)")
    func userInitSuppresses() {
        let s = parseStruct("""
        struct Q {
            let id: Int
            init(id: Int) { self.id = id }
        }
        """)
        #expect(InitSynthesis.memberwiseInit(for: s, access: "") == nil)
    }

    @Test("No stored properties → an empty init")
    func emptyInit() {
        let s = parseStruct("struct Q { var tags: Set<String> { [] } }")
        #expect(InitSynthesis.memberwiseInit(for: s, access: "")?.trimmedDescription == "init() {}")
    }

    @Test("static/computed members are skipped — only instance storage is initialized")
    func skipsStaticAndComputed() {
        let s = parseStruct("""
        struct Q {
            let id: Int
            static let shared = 0
            var derived: Int { id * 2 }
        }
        """)
        #expect(InitSynthesis.memberwiseInit(for: s, access: "")?.trimmedDescription == """
        init(id: Int) {
            self.id = id
        }
        """)
    }
}
