#if canImport(Testing)
@testable import CompilerCore
import Testing

/// BUG-219: an unresolved return type parameter nested inside a lambda's
/// contextual return type must not reject a concrete member-call result before
/// the enclosing higher-order call can infer that parameter.
@Suite
struct Bug219GenericLambdaMemberResolutionTests {
    @Test func testConcreteMemberCallInfersNestedLambdaReturnTypeParameter() throws {
        let source = """
        class Sample(val suffix: String) {
            fun describeList(): List<String> = listOf(suffix)
        }

        fun <R> apply(block: () -> List<R>): List<R> = block()
        fun <R> applyRelated(value: R, block: (R) -> List<R>): List<R> = block(value)

        fun probe(): List<String> {
            val sample = Sample("x")
            val result = apply { sample.describeList() }
            val relatedResult = applyRelated("related") { sample.describeList() }
            return result + relatedResult
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testPrimitiveAndFunctionValueControlsRemainValid() throws {
        let source = """
        fun <T, R> apply(value: T, block: (T) -> R): R = block(value)

        fun probe(): Int {
            val increment: (Int) -> Int = { it.plus(1) }
            return apply(1) { increment(it) }
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
