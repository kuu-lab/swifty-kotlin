#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-1927: retain the infix suffix after `when` without absorbing declarations.
@Suite
struct WhenInfixDeclarationBoundaryTests {
    @Test(arguments: [false, true], ["fun after() = 4", "class After", "val after = 4"])
    func whenInfixKeepsItsSuffixAndFollowingDeclaration(member: Bool, following: String) throws {
        let prefix = member ? "class Demo {\nprivate " : ""
        let function = """
        fun choose(flag: Boolean): Pair<Int, Int> = when (flag) {
            true -> 1
            false -> 2
        } to 3
        """
        let source = prefix + function + "\n" + following + (member ? "\n}" : "")
        let parsed = parse(source)
        let choose = try #require(parsed.arena.nodes.first { $0.kind == .funDecl })

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(choose.range.end.offset == prefix.utf8.count + function.utf8.count)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == (following.hasPrefix("fun") ? 2 : 1))
        #expect(parsed.arena.nodes.count { $0.kind == .classDecl } == (member ? 1 : 0) + (following.hasPrefix("class") ? 1 : 0))
        #expect(parsed.arena.nodes.count { $0.kind == .propertyDecl } == (following.hasPrefix("val") ? 1 : 0))
    }
}
#endif
