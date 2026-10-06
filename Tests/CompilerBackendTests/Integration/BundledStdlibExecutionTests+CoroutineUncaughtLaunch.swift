#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    /// Compile `source` to an executable and run it, returning the full
    /// `CommandResult` (including stderr and a non-zero exit captured rather
    /// than thrown). These cases need stderr access because uncaught launch
    /// failures are JVM-style `Exception in thread ...` reports there.
    private func compileAndRunCapturingAll(
        _ source: String,
        moduleName: String = "UncaughtLaunch"
    ) throws -> CommandResult {
        var runResult: CommandResult?
        try withTemporaryFile(contents: source) { path in
            let fm = FileManager.default
            let outputBase = fm.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? fm.removeItem(atPath: outputBase) }

            let options = makeTestOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)
            try assertCompilationSucceeded(result)

            do {
                runResult = try CommandRunner.run(executable: outputBase, arguments: [])
            } catch let CommandRunnerError.nonZeroExit(failed) {
                runResult = failed
            }
        }
        guard let runResult else {
            throw TestCompilationFailure(description: "run did not produce a result")
        }
        return runResult
    }

    /// KUU-1422: an uncaught `launch` failure inside `supervisorScope` must
    /// produce a JVM-style uncaught report on stderr — not the quiet
    /// `CoroutineExceptionHandler:` print that made it look handled — while
    /// supervisor semantics still hold: the sibling finishes, the caller
    /// continues, and the process exits 0 (verified JVM behavior).
    @Test
    func testSupervisorScopeUncaughtLaunchReportsOnStderr() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                supervisorScope {
                    launch { delay(10); println("sup-sib-alive") }
                    launch { delay(1); throw IllegalStateException("y") }
                }
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "sup-sib-alive\nafter\n")
        #expect(
            result.stderr.contains(
                "Exception in thread \"main\" java.lang.IllegalStateException: y"
            ),
            "expected JVM-style uncaught report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: a CoroutineExceptionHandler in the launch context still
    /// consumes the failure — the uncaught report must not also fire.
    @Test
    func testExplicitCoroutineExceptionHandlerStillConsumes() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val handler = CoroutineExceptionHandler { _, _ -> println("ceh-hit") }
                supervisorScope {
                    launch { delay(10); println("sup-sib-alive") }
                    launch(handler) { delay(1); throw IllegalStateException("y") }
                }
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "ceh-hit\nsup-sib-alive\nafter\n")
        #expect(
            !result.stderr.contains("Exception in thread"),
            "explicit CEH should suppress the uncaught report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: `async` keeps deferred semantics — an unawaited failure stays
    /// silent on the JVM too, so no report may fire here.
    @Test
    func testUnawaitedAsyncFailureStaysSilent() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                supervisorScope {
                    val d = async { delay(1); throw IllegalStateException("y") }
                    launch { delay(10); println("sup-sib-alive") }
                }
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "sup-sib-alive\nafter\n")
        #expect(
            !result.stderr.contains("Exception in thread"),
            "unawaited async must not report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: `GlobalScope.launch` is a root coroutine — the JVM reports
    /// its uncaught failure on stderr and keeps running (exit 0). Previously
    /// the failure was absorbed by a scope nobody ever waits on.
    @Test
    func testGlobalScopeLaunchFailureReportsOnStderr() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val j = GlobalScope.launch { throw IllegalStateException("y") }
                j.join()
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "after\n")
        #expect(
            result.stderr.contains("java.lang.IllegalStateException: y"),
            "expected uncaught report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: a stored `CoroutineScope(Job())` launch is a root coroutine
    /// whose failure the JVM reports — the bare Job() chain has no
    /// `handlesException` ancestor — while siblings and the caller continue.
    @Test
    func testStoredCoroutineScopeRootJobLaunchReports() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val s = CoroutineScope(Job())
                val j = s.launch { throw IllegalStateException("y") }
                j.join()
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "after\n")
        #expect(
            result.stderr.contains("java.lang.IllegalStateException: y"),
            "expected uncaught report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: non-supervisor propagation is unchanged — a child failure in
    /// a plain `runBlocking` reaches the top-level panic path (exit 1), and
    /// must NOT also emit the uncaught-coroutine report (the JVM is silent
    /// here when the rethrown failure is caught, and reports only once via
    /// `main` when it isn't).
    @Test
    func testPlainRunBlockingLaunchStillPropagates() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                launch { delay(10); println("sib") }
                launch { delay(1); throw IllegalStateException("y") }
                println("after")
            }
            """
        )
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("KSWIFTK-LINK-0003"))
        #expect(
            !result.stderr.contains("Exception in thread"),
            "propagated failure must not double-report, got stderr: \(result.stderr)"
        )
    }

    /// KUU-1422: the absorbed-propagation path must stay silent — a caught
    /// `runBlocking { launch { throw } }` produces no stderr report on JVM.
    @Test
    func testCaughtRunBlockingLaunchDoesNotReport() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() {
                try {
                    runBlocking {
                        launch { delay(10); println("sib") }
                        launch { delay(1); throw IllegalStateException("y") }
                        println("after")
                    }
                } catch (t: Throwable) {
                    println("caught")
                }
                println("done")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "after\ncaught\ndone\n")
        #expect(
            !result.stderr.contains("Exception in thread"),
            "caught propagation must not report, got stderr: \(result.stderr)"
        )
    }
}
#endif
