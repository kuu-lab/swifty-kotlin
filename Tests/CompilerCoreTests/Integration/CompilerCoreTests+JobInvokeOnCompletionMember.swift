#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

extension CompilerCoreTests {
    /// Upstream kotlinx.coroutines declares `invokeOnCompletion` on the `Job`
    /// interface, so callers use it after importing only `kotlinx.coroutines.Job`.
    /// The bundled stdlib used to expose it as a top-level extension instead,
    /// which left Ktor's `ByteChannelUtils.attachJob` unresolved
    /// (KSWIFTK-SEMA-0024). It must resolve as a member.
    @Test func testJobInvokeOnCompletionResolvesAsMemberWithoutImport() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.Job

        fun attach(job: Job) {
            job.invokeOnCompletion { }
            job.invokeOnCompletion(onCancelling = true) { }
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
