@testable import CompilerCore
import Testing

/// KSP-1355: Validates that the `Sequence<T>.reduce` family
/// (`reduce`, `reduceOrNull`, `reduceIndexed`, `reduceIndexedOrNull`) resolves
/// via the canonical `kotlin.sequences` source declarations with the
/// `<S, T : S>` accumulator widening contract.
@Suite
struct SequenceReduceFunctionTests {
    @Test func testSequenceReduceFamilyResolvesToCanonicalSource() throws {
        let ctx = makeContextFromSource("""
        fun sumValues(values: Sequence<Int>): Int {
            return values.reduce { acc, value -> acc + value }
        }

        fun sumValuesOrNull(values: Sequence<Int>): Int? {
            return values.reduceOrNull { acc, value -> acc + value }
        }

        fun indexedSum(values: Sequence<Int>): Int {
            return values.reduceIndexed { index, acc, value -> acc + index * value }
        }

        fun indexedSumOrNull(values: Sequence<Int>): Int? {
            return values.reduceIndexedOrNull { index, acc, value -> acc + index * value }
        }

        fun widenedAccumulator(values: Sequence<Int>): Number {
            return values.reduce { acc: Number, value -> acc.toInt() + value }
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            Comment(rawValue: "Expected Sequence reduce family to type-check, got: \(errors.map { "\($0.code): \($0.message)" })")
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        for name in ["reduce", "reduceOrNull", "reduceIndexed", "reduceIndexedOrNull"] {
            let callExprID = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == name
            }, "Expected \(name) member call")

            let binding = try #require(sema.bindings.callBinding(for: callExprID))
            let chosenCallee = try #require(binding.chosenCallee)
            let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                .map { ctx.interner.resolve($0) }
            #expect(fqName == ["kotlin", "sequences", name])
            #expect(
                sema.symbols.isSourceBackedSymbol(chosenCallee),
                "Expected Sequence.\(name) to resolve to bundled source"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }
}
