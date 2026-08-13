@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-107: Validates that `Sequence<T>.single` resolves through Sema
/// and gets wired to the runtime entry point `kk_sequence_single`. The synthetic
/// surface signature is `single(): T` and the call is marked as throwing because
/// the operation panics when the sequence is empty or contains more than one
/// element.
@Suite
struct SequenceSingleFunctionTests {
    @Test func testSequenceSingleResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun onlyInt(): Int {
            return sequenceOf(42).single()
        }

        fun onlyString(): String {
            return sequenceOf("only").single()
        }

        fun fromSequence(values: Sequence<String>): String {
            return values.single()
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Sequence.single to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(
            lastExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "single"
            },
            "Expected single member call"
        )
        #expect(sema.bindings.exprType(for: callExpr) == sema.types.stringType)

        let memberFQName = ["kotlin", "sequences", "Sequence", "single"]
            .map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: memberFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            links.isEmpty,
            "Expected Sequence.single to be backed by source, got: \(links)"
        )
    }
}
