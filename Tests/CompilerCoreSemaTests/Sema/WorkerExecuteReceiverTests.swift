@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct WorkerExecuteReceiverTests {
    @Test(arguments: [false, true])
    func rejectsBoundAndOpaqueJobs(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker
        class Job {
            fun run(input: Int): Int = input + 7
            fun probe(worker: Worker) {
                worker.execute(TransferMode.SAFE, { 35 }, this::run)
                worker.execute(TransferMode.SAFE, { 35 }, ::run)
                worker.execute(TransferMode.SAFE, { 35 }, Job()::run)
                val value: (Int) -> Int = { it + 7 }
                worker.execute(TransferMode.SAFE, { 35 }, value)
            }
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 4, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0430" })
        }
    }

    @Test(arguments: [false, true])
    func rejectsTransitiveJobCaptures(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.withWorker
        fun probe() = withWorker {
            val seed = 7
            fun captured(input: Int): Int = input + seed
            val callback: (Int) -> Int = { it + 7 }
            execute(TransferMode.SAFE, { 35 }) { input -> run { input + seed } }
            execute(TransferMode.SAFE, { 35 }, ::captured)
            execute(TransferMode.SAFE, { 35 }) { input -> run { callback(input) } }
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runToKIR(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 3, "\(errors)")
            #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0430" })
        }
    }

    @Test(arguments: [false, true])
    func rejectsOnlyCapturingJob(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker
        import kotlin.native.concurrent.withWorker

        fun job(input: Int): Int = input + 7
        fun probe() {
            val seed = 35
            withWorker {
                execute(TransferMode.SAFE, { seed }) { input -> input + 7 }
                this.execute<Int, Int>(TransferMode.SAFE, { seed }, ::job)
                execute(TransferMode.SAFE, { seed }) { input -> input + seed }
            }
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1, "\(errors)")
            #expect(errors.first?.code == "KSWIFTK-SEMA-0430")
        }
    }

    @Test(arguments: [false, true])
    func acceptsNonCapturingPrimitiveJob(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker

        fun probe(worker: Worker): Int {
            val future = worker.execute(TransferMode.SAFE, { 21 }) { input -> input * 2 }
            return future.result
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            // KUU-3849: a primitive-parameter job lambda is boxed for the
            // erased function-value ABI before this call lowers, so its KIR
            // captureArguments hold the (fnPtr, closureRaw) ABI slot rather
            // than semantic captures. The Worker.execute check must read the
            // underlying lambda's definition-site captures via unboxedSymbol
            // instead of reporting SEMA-0430 for that ABI slot.
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true])
    func receiverMemberWinsOverUserExtension(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        try withTemporaryFile(contents: """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)
        import kotlin.native.concurrent.TransferMode
        import kotlin.native.concurrent.Worker
        import kotlin.native.concurrent.Future
        import kotlin.native.concurrent.withWorker

        fun <T, R> Worker.execute(mode: TransferMode, producer: () -> T, job: (T) -> R): String = "extension"
        fun probe() = withWorker {
            val implicit: Future<Int> = execute(TransferMode.SAFE, { 35 }) { it + 7 }
            val explicit: Future<Int> = this.execute(TransferMode.SAFE, { 35 }) { it + 7 }
            implicit.result + explicit.result
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
