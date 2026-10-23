#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KUU-2787: `val xs: List<Int> = ints.fold(emptyList()) { acc, x -> acc + x }`
/// fixed the accumulator `R` to the initial value's `List<Nothing>` and pinned
/// the lambda body's expected type to it, so `acc + x` failed with
/// KSWIFTK-TYPE-0001. With a class-typed expected type, an initial type with
/// uninferred (`Nothing`) arguments now widens to the lambda's result type, as
/// kotlinc's `R :> initial, R :> lambda result` constraint system does. kotlinc
/// still rejects the call when nothing constrains `R`, so that case must too.
@Suite
struct FoldUninferredAccumulatorInferenceTests {
    @Test func testFoldWithEmptyListInitialWidensToExpectedTypeAndLambdaResult() throws {
        let source = """
        fun openDoors(doors: List<Boolean>): List<Int> =
            doors.foldIndexed(emptyList()) { i, acc, door -> if (door) acc + (i + 1) else acc }

        fun main() {
            val expected: List<Int> = listOf(1, 2, 3).fold(emptyList()) { acc, x -> acc + x }
            val explicit = listOf(1, 2, 3).fold(emptyList<Int>()) { acc, x -> acc + x }
            val total: Int = expected.sum() + explicit.sum() + openDoors(listOf(true, false)).sum()
            println(total)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testFoldWithEmptyListInitialStillRejectsMismatchedExpectedType() throws {
        let source = """
        fun main() {
            val wrong: List<String> = listOf(1, 2, 3).fold(emptyList()) { acc, x -> acc + x }
            println(wrong)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected List<Int> accumulator to be rejected for List<String>")
        }
    }

    @Test func testFoldWithEmptyListInitialWithoutExpectedTypeStaysRejectedLikeKotlinc() throws {
        let source = """
        fun main() {
            val unconstrained = listOf(1, 2, 3).fold(emptyList()) { acc, x -> acc + x }
            println(unconstrained)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "kotlinc rejects fold(emptyList()) with no expected type")
        }
    }
}
#endif
