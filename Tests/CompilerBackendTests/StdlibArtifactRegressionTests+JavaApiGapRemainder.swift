@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testJavaApiGapRemainder() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import java.lang.Runnable
        import java.lang.ref.SoftReference
        import java.lang.ref.WeakReference
        import java.util.concurrent.Callable
        import java.util.concurrent.CompletableFuture
        import java.util.concurrent.CountDownLatch
        import java.util.concurrent.Executors
        import java.util.concurrent.TimeUnit
        import java.util.logging.Handler
        import java.util.logging.Level
        import java.util.logging.LogManager
        import java.util.logging.LogRecord
        import java.util.logging.Logger
        import java.util.prefs.Preferences
        import java.util.function.Supplier
        import java.util.zip.Deflater

        class CapturingHandler : Handler() {
            var message: String? = null
            override fun publish(record: LogRecord) {
                message = record.message
            }
        }

        fun main() {
            val target = Any()
            val weak = WeakReference(target)
            println(weak.get() === target)
            weak.clear()
            println(weak.get() == null)
            val soft = SoftReference(target)
            println(soft.get() === target)
            soft.clear()
            println(soft.get() == null)

            val preferences = Preferences.userRoot().node("/codex/kuu4441")
            preferences.putInt("count", 42)
            preferences.node("child").put("key", "value")
            preferences.putByteArray("bytes", byteArrayOf(1, 2, 3))
            println(preferences.getInt("count", -1))
            println(preferences.nodeExists("child"))
            println(preferences.getByteArray("bytes", null)!!.contentEquals(byteArrayOf(1, 2, 3)))

            val deflater = Deflater()
            deflater.setInput(byteArrayOf(65, 66, 67))
            deflater.finish()
            val buffer = ByteArray(32)
            val compressed = mutableListOf<Byte>()
            while (!deflater.finished()) {
                val count = deflater.deflate(buffer)
                for (index in 0 until count) compressed.add(buffer[index])
            }
            println(compressed[0] == 0x78.toByte() && compressed[1] == 0x9C.toByte())
            println(compressed.size)
            println(deflater.getBytesRead())

            println(CompletableFuture.completedFuture("a").thenApplyAsync { it + "b" }.get())
            println(CompletableFuture.completedFuture("accepted").thenAcceptAsync { println(it) }.get() == Unit)
            println(CompletableFuture.completedFuture("done").thenRun(Runnable {}).get() == Unit)
            println(CompletableFuture.completedFuture(7).handle { value, failure -> value == 7 && failure == null }.get())
            println(CompletableFuture.failedFuture<Int>(IllegalArgumentException("x")).exceptionally { 9 }.get())
            println(CompletableFuture.completedFuture(2).thenApply { it + 3 }.get())
            println(CompletableFuture.supplyAsync(Supplier { 8 }).get())
            println(CompletableFuture.runAsync(Runnable {}).get() == Unit)

            val scheduler = Executors.newScheduledThreadPool(1)
            println(scheduler.schedule(Callable { "scheduled" }, 1L, TimeUnit.MILLISECONDS).get())
            val latch = CountDownLatch(2)
            val periodic = scheduler.scheduleAtFixedRate(Runnable { latch.countDown() }, 0L, 1L, TimeUnit.MILLISECONDS)
            println(latch.await(5L, TimeUnit.SECONDS))
            println(periodic.cancel(false))
            scheduler.shutdown()
            println(scheduler.awaitTermination(5L, TimeUnit.SECONDS))

            val logger = Logger.getLogger("codex.kuu4441")
            logger.setUseParentHandlers(false)
            val handler = CapturingHandler()
            logger.addHandler(handler)
            logger.log(Level.WARNING, "captured")
            println(handler.message == "captured")
            logger.removeHandler(handler)
            println(LogManager.getLogManager().getLogger("codex.kuu4441") === logger)
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            for optLevel in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let context = try runCodegenPipeline(
                    inputPath: inputPath,
                    moduleName: "JavaApiGapRemainder_\(optLevel.rawValue)",
                    outputPath: outputPath,
                    optLevel: optLevel,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath,
                    prepareTestStdlibCache: false
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            true
            true
            true
            true
            42
            true
            true
            true
            19
            3
            ab
            accepted
            true
            true
            true
            9
            5
            8
            true
            scheduled
            true
            true
            true
            true
            true

            """)
            }
        }
    }
}
