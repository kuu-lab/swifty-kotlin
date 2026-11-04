#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4042: `Result.fold`'s shared `R` must be inferred from both transform
/// results. The failure transform is analysed with `R` still open, so
/// `err.fold({ it + 1 }, { it.message })` joins `Int` and `String?` instead of
/// pinning `R` to the success transform's `Int` and failing with a return
/// type mismatch on `it.message`.
@Suite
struct ResultFoldLambdaInferenceTests {
    @Test func testFoldJoinsBothTransformReturnTypes() throws {
        let source = """
        fun main() {
            val err: Result<Int> = Result.failure(IllegalStateException("e1"))
            println(err.fold({ it + 1 }, { it.message }))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    @Test func testFoldNamedArgumentsJoinBothTransformReturnTypes() throws {
        let source = """
        fun main() {
            val err: Result<Int> = Result.failure(IllegalStateException("e1"))
            println(err.fold(onSuccess = { it + 1 }, onFailure = { it.message }))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    @Test func testFoldStillRejectsTransformReturnOutsideExpectedType() throws {
        let source = """
        fun main() {
            val err: Result<Int> = Result.failure(IllegalStateException("e1"))
            val folded: Int = err.fold({ "s" }, { "t" })
            println(folded)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            assertHasDiagnostic("KSWIFTK-SEMA-0469", in: ctx)
        }
    }

    /// The same shared-variable shape on a user-declared generic call:
    /// an earlier lambda's inferred type must not seed a variable that only
    /// occurs in the next lambda's return position.
    @Test func testGenericCallJoinsSharedLambdaReturnVariable() throws {
        let source = """
        fun <R> myFold(x: Int, ok: (Int) -> R, fail: (Throwable) -> R): R = ok(x)
        fun main() {
            println(myFold(3, { it + 1 }, { it.message }))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    /// `R` occurring in the accumulator lambda's input position must still be
    /// pinned by the seed argument, exactly like `Iterable.fold`.
    @Test func testAccumulatorLambdaStillPinsSharedInputVariable() throws {
        let source = """
        fun <A, R> accumulate(seed: R, values: List<A>, op: (R, A) -> R): R = seed
        fun main() {
            println(accumulate(0, listOf(1, 2)) { acc, e -> acc + e })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
#endif
