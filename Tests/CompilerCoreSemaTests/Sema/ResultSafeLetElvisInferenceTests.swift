#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

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
            """
            package resultElvisMemberCompanion
            import kotlin.coroutines.*
            interface Task { val continuation: Continuation<Unit> }
            class Write(override val continuation: Continuation<Unit>) : Task {
                fun resume() = continuation.resumeWith(RESUME)
                fun resume(throwable: Throwable? = null) =
                    continuation.resumeWith(throwable?.let { Result.failure(it) } ?: RESUME)
                companion object { val RESUME = Result.success(Unit) }
            }
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
                "KSWIFTK-SEMA-0469",
                in: diagnosticsForPath(paths[2], in: ctx)
            )
            assertNoDiagnostic(
                "KSWIFTK-TYPE-0001",
                in: diagnosticsForPath(paths[3], in: ctx)
            )
            let memberCompanionDiagnostics = diagnosticsForPath(paths[4], in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-INFER", in: memberCompanionDiagnostics)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: memberCompanionDiagnostics)
        }
    }

    @Test
    func testDirectArgumentResultFailureUsesParameterTypeVariable() throws {
        // `Result.failure`'s type parameter appears only in its return type,
        // so a direct argument needs the outer parameter's `Result<T>`
        // propagated as its expected type. A class type parameter
        // (`Gun<TSubject>`) is rigid in the caller and binds the nested call's
        // `T` — this is ktor-utils' `SuspendFunctionGun.resumeRootWith`
        // (KUU-3916). A callee *function* type parameter the expected type
        // cannot pin stays underdetermined, matching kotlinc (KUU-3908).
        let sources = [
            """
            package resultClassTypeParam
            class Gun<TSubject> {
                fun resumeRootWith(result: Result<TSubject>) {}
                fun test(exception: Throwable) {
                    resumeRootWith(Result.failure(exception))
                }
            }
            """,
            """
            package resultConcreteParam
            fun takesResultInt(r: Result<Int>) {}
            fun g(e: Throwable) {
                takesResultInt(Result.failure(e))
            }
            """,
            """
            package resultNamedArgument
            class Gun<TSubject> {
                fun resumeRootWith(tag: Int, result: Result<TSubject>) {}
                fun test(exception: Throwable) {
                    resumeRootWith(tag = 0, result = Result.failure(exception))
                }
            }
            """,
            """
            package resultReturnPinned
            fun <T> takesResult(r: Result<T>): T = r.getOrThrow()
            fun <T> f(e: Throwable): T = takesResult(Result.failure(e))
            """,
            """
            package resultUnderdetermined
            fun <T> takesResult(r: Result<T>) {}
            fun <T> f(e: Throwable) {
                takesResult(Result.failure(e))
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(4) {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-INFER", in: diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: diagnostics)
            }
            assertHasDiagnostic(
                "KSWIFTK-SEMA-INFER",
                in: diagnosticsForPath(paths[4], in: ctx)
            )
        }
    }

    /// An extension's own type parameter is only bounded by the receiver:
    /// `Array<out T>.contentDeepEquals(Array<out T>)` takes differently typed
    /// arrays with `T` inferred as their common supertype, so the receiver's
    /// argument must not become the nested argument call's expected type.
    @Test
    func testExtensionTypeParameterIsNotPinnedByReceiverForNestedArgument() throws {
        let source = """
        package extensionReceiverTypeParameter
        class Box<out T>(val value: T)
        fun <T> box(value: T): Box<T> = Box(value)
        fun <T> Box<out T>.sameShape(other: Box<out T>): Boolean = true
        fun check(): Boolean = box(1).sameShape(box("s"))
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
