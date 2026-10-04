@testable import CompilerCore
import Foundation
import Testing

@Suite
struct StringToIntOrNullFunctionTests {
    @Test
    func testStringToIntOrNullResolvesInSource() throws {
        let source = """
        fun probeNoRadix(text: String) {
            val result: Int? = text.toIntOrNull()
            println(result)
        }

        fun probeRadix(text: String) {
            val result: Int? = text.toIntOrNull(16)
            println(result)
        }

        fun probeLiteral(): Int {
            val parsed: Int? = "42".toIntOrNull()
            return parsed ?: 0
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected String.toIntOrNull overloads to type-check cleanly, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let noRadixCall = try #require(
            firstExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "toIntOrNull"
                    && args.isEmpty
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to toIntOrNull() in AST"
        )
        #expect(
            sema.bindings.exprType(for: noRadixCall) == sema.types.makeNullable(sema.types.intType)
        )

        let radixCall = try #require(
            firstExprID(in: ast) { exprID, expr in
                guard case let .memberCall(_, callee, _, args, _) = expr,
                      let range = ast.arena.exprRange(exprID)
                else { return false }
                return interner.resolve(callee) == "toIntOrNull"
                    && args.count == 1
                    && !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            },
            "Expected member call to toIntOrNull(radix) in AST"
        )
        #expect(
            sema.bindings.exprType(for: radixCall) == sema.types.makeNullable(sema.types.intType)
        )

        let fqName = ["kotlin", "text", "toIntOrNull"].map { interner.intern($0) }
        let links = Set(sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            !links.contains("kk_string_toIntOrNull_flat") && !links.contains("__kk_string_toIntOrNull_flat"),
            "String.toIntOrNull should not expose a kk_ or __kk_ external link; got: \(links)"
        )
        #expect(
            !links.contains("kk_string_toIntOrNull_radix_flat") && !links.contains("__kk_string_toIntOrNull_radix_flat"),
            "String.toIntOrNull(radix) should not expose a kk_ or __kk_ external link; got: \(links)"
        )

        let bridgeLinks = Set(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toIntOrNull"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
            + sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toIntOrNull_radix"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            bridgeLinks.contains("__kk_string_toIntOrNull") && bridgeLinks.contains("__kk_string_toIntOrNull_radix"),
            "Private __kk_string_toIntOrNull bridges should be registered; got: \(bridgeLinks)"
        )
    }
}
