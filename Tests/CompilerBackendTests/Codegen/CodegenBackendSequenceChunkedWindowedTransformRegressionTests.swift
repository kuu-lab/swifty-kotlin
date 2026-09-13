#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceChunkedWindowedTransformRegressionTests {

    /// Regression coverage for a family of bugs in `Sequence<T>.chunked(size,
    /// transform)` / `.windowed(size, step, partialWindows, transform)`:
    ///
    /// - A SIGBUS crash: these overloads have real Kotlin-source declarations
    ///   (SequenceWindowChunk.kt) with a function-typed parameter, so
    ///   KIRLoweringDriver's auto-inline heuristic always inlines them at the
    ///   call site. The caller wraps the transform lambda into a
    ///   `kk_function_create_1` handle (the normal function-value ABI for
    ///   calling a real, non-inline-keyword Kotlin function), but the inlined
    ///   body forwards that already-wrapped handle straight to the native
    ///   `kk_sequence_chunked_transform` / `kk_sequence_windowed_transform`
    ///   bridge, which expects the raw `(fnPtr, closureRaw)` pair used
    ///   elsewhere for collection HOF lambdas -- jumping into the wrapper
    ///   object's heap memory as if it were code.
    /// - Wrong-overload resolution when a trailing lambda's defaulted middle
    ///   parameters are skipped (`windowed(3) { ... }`): candidate matching
    ///   required the callee's own parameter count to equal the caller's
    ///   provided argument count, so it never matched the 4-param
    ///   transform-taking overload and silently fell back to the unrelated
    ///   3-param no-transform overload declared first in source.
    /// - An uncaught exception escaping past the caller's own try/catch:
    ///   `checkWindowSizeStep`'s validation throw, compiled assuming it
    ///   propagates via its caller's own outThrown parameter (correct for a
    ///   standalone function), instead propagated via the *inlined-into*
    ///   function's outThrown once auto-inlining spliced it into a caller
    ///   with its own enclosing try/catch.
    /// - A dropped captured variable when defaults are skipped: the argument
    ///   materialization step that wraps the transform lambda indexed the
    ///   user-provided source arguments by declared parameter position, which
    ///   is wrong once skipped defaults desync the two lists.
    @Test
    func testCodegenSequenceChunkedWindowedTransformRegression() throws {
        let source = try diffCaseSource("sequence_chunked_windowed_transform.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceChunkedWindowedTransformRegression",
            expected:
                """
                [3, 7, 5]
                [6, 9, 12]
                [6, 9, 12]
                [3, 7]
                [103, 107, 105]
                [106, 109, 112]
                [106, 109, 112]
                []
                []
                chunked(0) transform: size 0 must be greater than zero.
                windowed(0) transform: Both size 0 and step 1 must be greater than zero.
                """
                + "\n"
        )
    }
}
#endif
