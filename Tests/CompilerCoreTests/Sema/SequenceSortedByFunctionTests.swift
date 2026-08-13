@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-111: Validates that `kotlin.sequences.Sequence<T>.sortedBy`
/// resolves via the bundled Kotlin source and has no runtime-bridge link.
@Suite
struct SequenceSortedByFunctionTests {
    @Test func testSequenceSortedByFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun sortByLength(values: Sequence<String>): Sequence<String> {
            return values.sortedBy { it.length }
        }

        fun sortByLengthFromGenerator(): Sequence<String> {
            return sequenceOf("cc", "a", "bbb").sortedBy { value -> value.length }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Sequence.sortedBy to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "sortedBy"
        }, "Expected sortedBy member call")

        let chosenCallee = try #require(
            sema.bindings.callBinding(for: callExprID)?.chosenCallee,
            "Expected sortedBy call to be bound"
        )
        #expect(
            sema.symbols.isSourceBackedSymbol(chosenCallee),
            "Expected Sequence.sortedBy to resolve to bundled source"
        )
    }
}
