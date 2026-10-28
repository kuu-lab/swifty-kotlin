@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IterableBoundedAccumulatorInferenceTests {
    @Test
    func receiverElementBoundPropagatesToLambdaAccumulator() throws {
        let ctx = makeContextFromSource("""
        package fixture
        fun <S, T : S> Iterable<T>.aggregate(operation: (S, T) -> S): S = iterator().next()
        fun sum(values: List<Int>): Int = values.aggregate { acc, x -> acc + x }
        fun setSum(values: Set<Int>): Int = values.aggregate { acc, x -> acc + x }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
