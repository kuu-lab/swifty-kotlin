#if canImport(Testing)
@testable import CompilerCore
import Testing

/// STDLIB-TEXT-PROP-019 / KSP-661: Validates that `Char.isWhitespace()` resolves
/// through Sema for plain Char receivers as well as literal / branch contexts.
/// The predicate is implemented in bundled Kotlin (kotlin.text.CharPredicates),
/// so the resolved symbol carries no synthetic runtime link.
@Suite
struct CharIsWhitespaceFunctionTests {
    @Test func testCharIsWhitespaceResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun whitespaceCheck(ch: Char): Boolean {
            return ch.isWhitespace()
        }

        fun whitespaceCheckLiteral(): Boolean {
            return ' '.isWhitespace()
        }

        fun whitespaceCheckTab(): Boolean {
            return '\t'.isWhitespace()
        }

        fun whitespaceCheckNonWhitespace(): Boolean {
            return 'A'.isWhitespace()
        }

        fun whitespaceCheckIfBranch(ch: Char): Int {
            return if (ch.isWhitespace()) 1 else 0
        }

        fun probe(ch: Char) {
            ch.isWhitespace()
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.isWhitespace() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let callExpr = try #require(
            firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return interner.resolve(callee) == "isWhitespace"
            },
            "Expected member call to isWhitespace in AST"
        )

        #expect(sema.bindings.exprTypes[callExpr] == sema.types.booleanType)
        let chosen = sema.bindings.callBinding(for: callExpr)?.chosenCallee
            ?? sema.bindings.identifierSymbol(for: callExpr)
        #expect(chosen.flatMap { sema.symbols.externalLinkName(for: $0) } == nil)

        let fq = ["kotlin", "text", "isWhitespace"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookupAll(fqName: fq).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == sema.types.charType
                    && signature.parameterTypes.isEmpty
            },
            "Expected synthetic kotlin.text.isWhitespace extension on Char"
        )
        #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        #expect(
            sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType,
            "Char.isWhitespace() should return Boolean"
        )
    }
}
#endif
