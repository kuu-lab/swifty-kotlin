@testable import CompilerCore
import Testing

/// STDLIB-SEQ-FN-024: Validates that `kotlin.sequences.Sequence<T>.filterIndexed`
/// resolves through the source-backed Sequence transform HOF implementation.
@Suite
struct SequenceFilterIndexedFunctionTests {
    @Test func testSequenceFilterIndexedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun pickIndexed(values: Sequence<Int>): Sequence<Int> {
            return values.filterIndexed { index, value -> index % 2 == 0 || value > 10 }
        }

        fun pickIndexedFromGenerator(): Sequence<Int> {
            return sequenceOf(10, 20, 30, 40).filterIndexed { index, _ -> index < 3 }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence.filterIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let callExprID = try #require(firstExprID(in: ast) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "filterIndexed"
        }, "Expected filterIndexed member call")
        let binding = try #require(sema.bindings.callBinding(for: callExprID))
        let chosenCallee = binding.chosenCallee
        #expect(
            sema.symbols.symbol(chosenCallee)?.declSite != nil,
            "Expected Sequence.filterIndexed call to resolve to the source-backed extension"
        )
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
    }
}
