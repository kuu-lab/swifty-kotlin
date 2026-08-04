@testable import CompilerCore
import Testing

/// KSP-408: Validates that `CharSequence.lastIndexOf` resolves through Sema for
/// the (Char, startIndex, ignoreCase) overload alongside the String overloads
/// (bundled Kotlin source, `StringIndexOf.kt`).
@Suite
struct StringLastIndexOfFunctionTests {
    @Test func testLastIndexOfResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun String.findDelimiter(delimiter: String): Int {
            return indexOf(delimiter)
        }

        fun lastChar(value: String): Int {
            return value.lastIndexOf('l')
        }

        fun findChar(value: CharSequence): Int {
            return value.lastIndexOf('o', 10, false)
        }

        fun findCharIgnoreCase(value: String): Int {
            return value.lastIndexOf('O', 10, true)
        }

        fun probe(value: CharSequence): Int {
            return value.lastIndexOf('z', 0, false)
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        var lastIndexOfCount = 0
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == "lastIndexOf",
                  let range = ast.arena.exprRange(exprID),
                  !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else { continue }
            lastIndexOfCount += 1
            #expect(
                sema.bindings.exprTypes[exprID] == sema.types.intType,
                "lastIndexOf must return Int"
            )
        }
        #expect(lastIndexOfCount == 4, "Expected four lastIndexOf calls in user source")
    }
}
