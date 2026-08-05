@testable import CompilerCore
import Testing

/// KSP-408: Validates that `CharSequence.contains` resolves through Sema for
/// `String` receivers across all of its stdlib overloads (bundled Kotlin source,
/// `StringIndexOf.kt`), including the `in` operator and the case-insensitive
/// overload. `contains(regex: Regex)` remains a separate synthetic stub.
@Suite
struct StringContainsFunctionTests {
    @Test func testContainsWithStringResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstring(s: String): Boolean {
            return s.contains("hello")
        }

        fun emptyNeedleAlwaysMatches(s: String): Boolean {
            return s.contains("")
        }

        fun literalReceiverContains(): Boolean {
            return "hello world".contains("world")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected contains(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testContainsWithIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstringIgnoreCase(s: String): Boolean {
            return s.contains("HELLO", true)
        }

        fun explicitCaseSensitive(s: String, needle: String): Boolean {
            return s.contains(needle, false)
        }

        fun namedIgnoreCase(s: String): Boolean {
            return s.contains("foo", ignoreCase = true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected contains(String, Boolean) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testContainsInOperatorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun substringViaInOperator(s: String, needle: String): Boolean {
            return needle in s
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected `in` operator on String to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testRegexInOperatorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun regexInString(r: Regex, s: String): Boolean {
            return r in s
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected `Regex in String` to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let regexInExprs = (0..<ast.arena.exprs.count).compactMap { i -> (ExprID, Expr)? in
            let exprID = ExprID(rawValue: Int32(i))
            guard let expr = ast.arena.expr(exprID),
                  case .inExpr = expr else { return nil }
            return (exprID, expr)
        }.filter { _, expr in
            guard case let .inExpr(lhs, rhs, _) = expr else { return false }
            guard let lhsType = sema.bindings.exprType(for: lhs),
                  let rhsType = sema.bindings.exprType(for: rhs) else { return false }
            let lhsName = sema.types.displayName(of: lhsType, symbols: sema.symbols, interner: ctx.interner)
            let rhsName = sema.types.displayName(of: rhsType, symbols: sema.symbols, interner: ctx.interner)
            return lhsName == "Regex" && rhsName == "String"
        }
        #expect(regexInExprs.count >= 1, "Expected at least one `Regex in String` expression")
        let firstInExpr = try #require(regexInExprs.first, "Expected one `Regex in String` expression").0
        let binding = sema.bindings.callBinding(for: firstInExpr)
        let link = binding.flatMap { sema.symbols.externalLinkName(for: $0.chosenCallee) }
        #expect(
            link == "kk_string_contains_regex_flat",
            "Expected `r in s` to bind to kk_string_contains_regex_flat, got \(link ?? "nil")"
        )
    }

}
