#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-018 / KSP-661: Validates that `Char.isUpperCase()` resolves
/// through Sema. The predicate is implemented in bundled Kotlin
/// (kotlin.text.CharPredicates), so it carries no synthetic runtime link.
@Suite
struct CharIsUpperCaseFunctionTests {
    @Test func testCharIsUpperCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun probe(ch: Char): Boolean {
            return ch.isUpperCase()
        }

        fun probeAtCallSite(ch: Char) {
            ch.isUpperCase()
        }
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Char.isUpperCase() to resolve, got: \(ctx.diagnostics.diagnostics)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "isUpperCase"
            },
            "Expected member call to isUpperCase in AST"
        )

        #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType)
        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        #expect(chosen.flatMap { sema.symbols.externalLinkName(for: $0) } == nil)

        let fq = ["kotlin", "text", "isUpperCase"].map { ctx.interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let charReceiverSymbol = candidates.first { symbolID in
            guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == sema.types.charType
                && signature.parameterTypes.isEmpty
                && signature.returnType == sema.types.booleanType
        }
        let symbol = try #require(
            charReceiverSymbol,
            "Char.isUpperCase should resolve to a bundled Kotlin extension"
        )
        #expect(sema.symbols.externalLinkName(for: symbol) == nil)
    }
}
#endif
