@testable import CompilerCore
import Foundation
import Testing

/// Verifies that `kotlin.text.String.toInt()` and `String.toInt(radix:)` —
/// tracked by STDLIB-TEXT-FN-099 — are source-backed after KSP-414 and bridge
/// through the private `__kk_string_toInt` runtime symbols.
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
            sema.symbols.externalLinkName(for: noArgCallee) == nil,
            "String.toInt() should be source-backed and have no public C link"
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
            sema.symbols.externalLinkName(for: radixCallee) == nil,
            "String.toInt(radix) should be source-backed and have no public C link"
        )

        let links = Set(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "toInt"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            !links.contains("kk_string_toInt") && !links.contains("__kk_string_toInt"),
            "String.toInt() should not expose a kk_ or __kk_ external link — got: \(links.sorted())"
        )
        #expect(
            !links.contains("kk_string_toInt_radix") && !links.contains("__kk_string_toInt_radix"),
            "String.toInt(radix) should not expose a kk_ or __kk_ external link — got: \(links.sorted())"
        )

        let privateBridgeLinks = Set(
            sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toInt"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
            + sema.symbols.lookupAll(fqName: ["kotlin", "text", "__kk_string_toInt_radix"].map { interner.intern($0) })
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            privateBridgeLinks.contains("__kk_string_toInt") && privateBridgeLinks.contains("__kk_string_toInt_radix"),
            "Private __kk_string_toInt bridges should be registered — got: \(privateBridgeLinks.sorted())"
        )
    }
}
