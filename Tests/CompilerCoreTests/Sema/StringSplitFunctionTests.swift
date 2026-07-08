@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-069: Validates that `CharSequence.split(delimiter, ignoreCase, limit)`
/// resolves through Sema for `String` receivers across all registered overloads.
///
/// The public overloads are loaded from `Stdlib/kotlin/text/StringSplitJoin.kt`;
/// that source delegates to private `__kk_string_split*` bridge stubs.
@Suite
struct StringSplitFunctionTests {
    private func assertPublicMemberCallIsSourceBacked(
        _ source: String,
        memberName: String,
        expectation: String
    ) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "\(expectation), got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExpr = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == memberName
        }, "Expected member call to \(memberName)")
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
            "Expected call binding for \(memberName)"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil,
            "Expected public \(memberName) to resolve to bundled Kotlin source"
        )
        #expect(
            sema.symbols.symbol(chosenCallee)?.declSite != nil,
            "Expected public \(memberName) to have a source declaration"
        )
    }

    @Test func testSplitWithDelimiterResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun splitCsv(s: String): List<String> {
            return s.split(",")
        }
        """,
            memberName: "split",
            expectation: "Expected split(delimiter) to type-check"
        )
    }

    @Test func testSplitWithLimitResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun splitFirstTwo(s: String): List<String> {
            return s.split(",", limit = 2)
        }
        """,
            memberName: "split",
            expectation: "Expected split(delimiter, limit) to type-check"
        )
    }

    @Test func testSplitWithIgnoreCaseResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun splitIgnoringCase(s: String): List<String> {
            return s.split("x", ignoreCase = true)
        }
        """,
            memberName: "split",
            expectation: "Expected split(delimiter, ignoreCase) to type-check"
        )
    }

    @Test func testSplitWithIgnoreCaseAndLimitResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun splitIgnoringCaseWithLimit(s: String): List<String> {
            return s.split("x", ignoreCase = true, limit = 3)
        }
        """,
            memberName: "split",
            expectation: "Expected split(delimiter, ignoreCase, limit) to type-check"
        )
    }

    @Test func testSplitOnStringLiteralResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun parts(): List<String> {
            return "a,b,c".split(",")
        }
        """,
            memberName: "split",
            expectation: "Expected split on a String literal to type-check"
        )
    }

    @Test func testSplitToSequenceResolvesInSource() throws {
        try assertPublicMemberCallIsSourceBacked("""
        fun parts(s: String): Sequence<String> {
            return s.splitToSequence(",")
        }
        """,
            memberName: "splitToSequence",
            expectation: "Expected splitToSequence(delimiter) to type-check"
        )
    }
}
