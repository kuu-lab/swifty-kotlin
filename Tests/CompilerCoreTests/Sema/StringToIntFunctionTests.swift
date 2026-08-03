@testable import CompilerCore
import Foundation
import Testing

/// Verifies that `kotlin.text.String.toInt()` and `String.toInt(radix:)` —
/// tracked by STDLIB-TEXT-FN-099 — are registered as synthetic stdlib stubs
/// and resolve to the correct runtime external link names at sema time.
@Suite
struct StringToIntFunctionTests {
    @Test
    func testStringToIntOverloadsResolveToRuntimeBridges() throws {
        let source = """
        fun parse(value: String): Int {
            return value.toInt()
        }

        fun parseHex(value: String): Int {
            return value.toInt(16)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "Expected String.toInt() overloads to resolve")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let noArgCall = try #require(
            lastExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "toInt"
                    && args.isEmpty
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to toInt() in AST"
        )

        let noArgCallee = try #require(
            sema.bindings.callBinding(for: noArgCall)?.chosenCallee,
            "Expected call binding for toInt()"
        )
        #expect(
            sema.symbols.externalLinkName(for: noArgCallee) == "kk_string_toInt",
            "String.toInt() should resolve to kk_string_toInt"
        )

        let radixCall = try #require(
            lastExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "toInt"
                    && args.count == 1
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to toInt(radix) in AST"
        )

        let radixCallee = try #require(
            sema.bindings.callBinding(for: radixCall)?.chosenCallee,
            "Expected call binding for toInt(radix)"
        )
        #expect(
            sema.symbols.externalLinkName(for: radixCallee) == "kk_string_toInt_radix",
            "String.toInt(radix) should resolve to kk_string_toInt_radix"
        )

        let links = Set(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "toInt"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.contains("kk_string_toInt"),
            "String.toInt() should be registered with kk_string_toInt — got: \(links.sorted())"
        )
        #expect(
            links.contains("kk_string_toInt_radix"),
            "String.toInt(radix) should be registered with kk_string_toInt_radix — got: \(links.sorted())"
        )
    }
}
