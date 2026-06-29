@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-042: Validates that `Sequence<T>.fold(initial: R, operation: (R, T) -> R): R`
/// resolves via the synthetic Sema member stub and links to the
/// `kk_sequence_fold` runtime entry point.
@Suite
struct SequenceFoldFunctionTests {
    @Test func testSequenceFoldResolvesToRuntimeABIWithMatchingResultType() throws {
        let ctx = makeContextFromSource("""
        fun sumValues(values: Sequence<Int>): Int {
            return values.fold(0) { acc, value -> acc + value }
        }

        fun concatValues(values: Sequence<Int>): String {
            return values.fold("") { acc, value -> acc + value.toString() }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.fold to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "fold"
        }, "Expected fold member call")

        let memberFQName = [
            "kotlin", "sequences", "Sequence", "fold",
        ].map(ctx.interner.intern)
        let foldMembers = sema.symbols.lookupAll(fqName: memberFQName)
        #expect(
            foldMembers.contains { sema.symbols.externalLinkName(for: $0) == "kk_sequence_fold" },
            "Expected Sequence.fold synthetic member to link to kk_sequence_fold"
        )

        #expect(sema.bindings.exprType(for: callExprID) == sema.types.intType)
    }
}
