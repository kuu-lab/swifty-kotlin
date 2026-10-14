#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct CompanionBlockParsingTests {
    @Test(arguments: [
        ("companion { fun f() = 1 }", 1, 0),
        ("companion\n{ fun f() = 1\nval value = 2 }", 1, 1),
        ("companion { fun f() = 1; fun g() = 2 }", 2, 0),
    ])
    func companionBlockMembersParseWithoutRecovery(
        body: String,
        expectedFunctions: Int,
        expectedProperties: Int
    ) {
        let parsed = parse("class C { \(body) }")

        #expect(parsed.diagnostics.diagnostics.isEmpty, "\(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.filter { $0.kind == .funDecl }.count == expectedFunctions)
        #expect(parsed.arena.nodes.filter { $0.kind == .propertyDecl }.count == expectedProperties)
    }
}
#endif
