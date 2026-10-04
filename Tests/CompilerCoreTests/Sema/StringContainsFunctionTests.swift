@testable import CompilerCore
import Testing

/// KSP-408: Validates that `CharSequence.contains` resolves through Sema for
/// `String` receivers across all of its stdlib overloads (bundled Kotlin source,
/// `StringIndexOf.kt`), including the `in` operator and the case-insensitive
/// overload. `contains(regex: Regex)` remains a separate synthetic stub.
@Suite
struct StringContainsFunctionTests {
    @Test func testContainsAndRegexInOperatorResolveInSource() throws {
        let sources: [String] = [
            """
            fun hasSubstring(s: String): Boolean {
                return s.contains("hello")
            }

            fun emptyNeedleAlwaysMatches(s: String): Boolean {
                return s.contains("")
            }

            fun literalReceiverContains(): Boolean {
                return "hello world".contains("world")
            }

            fun hasSubstringIgnoreCase(s: String): Boolean {
                return s.contains("HELLO", true)
            }

            fun explicitCaseSensitive(s: String, needle: String): Boolean {
                return s.contains(needle, false)
            }

            fun namedIgnoreCase(s: String): Boolean {
                return s.contains("foo", ignoreCase = true)
            }

            fun substringViaInOperator(s: String, needle: String): Boolean {
                return needle in s
            }
            """,
            """
            fun regexInString(r: Regex, s: String): Boolean {
                return r in s
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected contains and `Regex in String` to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
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
            let binding = try #require(sema.bindings.callBinding(for: firstInExpr))
            let calleeName = sema.symbols.symbol(binding.chosenCallee).flatMap { ctx.interner.resolve($0.name) }
            #expect(
                calleeName == "contains",
                "Expected `r in s` to bind to String.contains, got \(calleeName ?? "nil")"
            )
        }
    }
}
