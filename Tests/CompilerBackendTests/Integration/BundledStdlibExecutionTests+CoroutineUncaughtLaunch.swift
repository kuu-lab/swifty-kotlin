#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
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

    @Test
    func testExplicitCoroutineExceptionHandlerStillConsumes() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                val handler = CoroutineExceptionHandler { _, exception ->
                    println("ceh-hit:${exception.message}")
                }
                supervisorScope {
                    launch { delay(10); println("sup-sib-alive") }
                    launch(handler) { delay(1); throw IllegalStateException("y") }
                }
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "ceh-hit:y\nsup-sib-alive\nafter\n")
        #expect(
            !result.stderr.contains("Exception in thread"),
            "explicit CEH should suppress the uncaught report, got stderr: \(result.stderr)"
        )
    }

    @Test
    func testUncaughtLaunchReportsSourceExceptionCauseChain() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            class LaunchFailure(message: String, cause: Throwable?) : Exception(message, cause)

            fun main() = runBlocking {
                supervisorScope {
                    launch {
                        throw LaunchFailure("launch-fail", IllegalStateException("inner"))
                    }
                    launch { delay(50); println("sib-alive") }
                }
                println("after")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "sib-alive\nafter\n")
        #expect(
            result.stderr.contains("Exception in thread \"main\" LaunchFailure: launch-fail"),
            "expected uncaught report header, got stderr: \(result.stderr)"
        )
        #expect(
            result.stderr.contains("Caused by: java.lang.IllegalStateException: inner"),
            "expected Caused by chain for object-box throwable, got stderr: \(result.stderr)"
        )
    }

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
        #expect(result.stderr.contains("Exception in thread \"main\" java.lang.IllegalStateException: y"))
        let reportCount = result.stderr.components(separatedBy: "Exception in thread").count - 1
        #expect(
            reportCount == 1,
            "propagated failure must report exactly once, got stderr: \(result.stderr)"
        )
    }

    @Test
    func testCaughtRunBlockingLaunchDoesNotReport() throws {
        let result = try compileAndRunCapturingAll(
            """
            import kotlinx.coroutines.*

            fun main() {
                var handled = false
                val handler = CoroutineExceptionHandler { _, _ -> handled = true }
                try {
                    runBlocking {
                        launch { delay(10); println("sib") }
                        launch(handler) { delay(1); throw IllegalStateException("y") }
                        println("after")
                    }
                } catch (t: Throwable) {
                    println("caught")
                }
                println("handled:$handled")
                println("done")
            }
            """
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "after\ncaught\nhandled:false\ndone\n")
        #expect(
            !result.stderr.contains("Exception in thread"),
            "caught propagation must not report, got stderr: \(result.stderr)"
        )
    }
}
#endif
