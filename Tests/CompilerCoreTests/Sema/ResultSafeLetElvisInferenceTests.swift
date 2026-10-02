#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ResultSafeLetElvisInferenceTests {
    @Test
    func testSafeLetFailureUsesElvisFallbackResultType() throws {
        let sources = [
            """
            package resultElvisCall
            val RESUME = Result.success(Unit)
            fun f(continuation: (Result<Unit>) -> Unit, throwable: Throwable?) =
                continuation(throwable?.let { Result.failure(it) } ?: RESUME)
            """,
            """
            package resultElvisLocal
            fun f(throwable: Throwable?): Result<Unit> {
                val fallback: Result<Unit> = Result.success(Unit)
                return throwable?.let { Result.failure(it) } ?: fallback
            }
            """,
            """
            package resultElvisMismatch
            val RESUME = Result.success(Unit)
            fun f(throwable: Throwable?): Result<String> =
                throwable?.let { Result.failure(it) } ?: RESUME
            """,
            """
            package ordinaryElvisHeterogeneous
            fun f(value: String?): Any = value?.let { "text" } ?: 42
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(2) {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-INFER", in: diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: diagnostics)
            }
            assertHasDiagnostic(
                "KSWIFTK-TYPE-0001",
                in: diagnosticsForPath(paths[2], in: ctx)
            )
            assertNoDiagnostic(
                "KSWIFTK-TYPE-0001",
                in: diagnosticsForPath(paths[3], in: ctx)
            )
        }
    }
}
#endif
