#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

extension CompilerCoreTests {
    /// KUU-4274: sources vendored into `kotlinx.coroutines` redeclare
    /// classifiers the bundled-stdlib artifact also exports (`CoroutineScope`,
    /// `CoroutineStart`, `Job`, `launch`, ...). The imported twin must not win
    /// qualifier or classifier-scope member resolution: enum entries and the
    /// `launch(start:)` argument have to bind the source-side `CoroutineStart`,
    /// otherwise initializer checks report KSWIFTK-SEMA-0468 and overload
    /// resolution reports KSWIFTK-SEMA-0002 (KUU-4275 is the same shape at
    /// `UnbiasedSelectBuilderImpl.initSelectResult`).
    @Test func testCoroutinesSourceDeclsShadowImportedStdlibArtifact() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        package kotlinx.coroutines

        import kotlin.coroutines.*

        interface CoroutineScope {
            val coroutineContext: CoroutineContext
        }

        fun CoroutineScope(context: CoroutineContext): CoroutineScope =
            object : CoroutineScope {
                override val coroutineContext: CoroutineContext get() = context
            }

        enum class CoroutineStart {
            DEFAULT, LAZY, ATOMIC, UNDISPATCHED;
            val isLazy: Boolean get() = this == LAZY
        }

        interface Job : CoroutineContext.Element {
            companion object Key : CoroutineContext.Key<Job>
            override val key: CoroutineContext.Key<*> get() = Key
        }

        object NonCancellable : Job {
            override val key: CoroutineContext.Key<*> get() = Job.Key
        }

        fun CoroutineScope.launch(
            context: CoroutineContext = EmptyCoroutineContext,
            start: CoroutineStart = CoroutineStart.DEFAULT,
            block: suspend CoroutineScope.() -> Unit
        ): Job = TODO()

        class Probe(val context: CoroutineContext) {
            fun getResult(): Any? {
                CoroutineScope(context).launch(start = CoroutineStart.UNDISPATCHED) {
                    println("x")
                }
                return null
            }
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0468", in: ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
    }
}
#endif
