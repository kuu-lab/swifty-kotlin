@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testConcurrentThreadStartsAndJoins() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.concurrent.thread
        import kotlin.concurrent.timer
        import kotlin.concurrent.schedule
        import java.util.concurrent.CountDownLatch
        import java.util.concurrent.TimeUnit

        fun main() {
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            val t = thread(start = false, isDaemon = true, name = "worker", priority = 7) {
                println(Thread.currentThread().name)
                println(Thread.currentThread().isDaemon)
                println(Thread.currentThread().priority)
                entered.countDown()
                release.await()
            }
            println(t.name)
            println(t.isAlive)
            t.start()
            println(entered.await(5L, TimeUnit.SECONDS))
            println(t.isAlive)
            release.countDown()
            t.join()
            println(t.isAlive)
            val periodic = CountDownLatch(1)
            val oneShot = CountDownLatch(1)
            var defaultTimerName = false
            val timer = timer(daemon = true, period = 1000L) {
                defaultTimerName = Thread.currentThread().name.startsWith("Timer-")
                periodic.countDown()
            }
            println(periodic.await(5L, TimeUnit.SECONDS))
            println(defaultTimerName)
            timer.schedule(0L) { oneShot.countDown() }
            println(oneShot.await(5L, TimeUnit.SECONDS))
            timer.cancel()
            try {
                thread(start = false, priority = 11) { }
            } catch (_: IllegalArgumentException) {
                println("invalid priority")
            }
            val failing = thread(name = "failing") { throw IllegalStateException("failure") }
            failing.join()
            println("survived")
            thread {
                Thread.sleep(100L)
                println("non-daemon finished")
            }
            println("main finished")
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let context = try runCodegenPipeline(inputPath: inputPath, moduleName: "ConcurrentThread", outputPath: outputPath, optLevel: .O0, allowDefaultStdlibLibrary: false, stdlibLibraryPath: artifactPath, prepareTestStdlibCache: false)
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: outputPath, arguments: [], timeout: 20)
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stderr.contains("Exception in thread \"failing\" java.lang.IllegalStateException: failure"))
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "worker\nfalse\nworker\ntrue\n7\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\ninvalid priority\nsurvived\nmain finished\nnon-daemon finished\n")
        }
    }
}
