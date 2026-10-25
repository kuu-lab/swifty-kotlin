@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-3366: Java utility facades missing from the bundled stdlib resolve and execute.
    @Test
    func testJavaUtilCompletenessSurface() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            val calendar = java.util.Calendar.getInstance()
            println(calendar.getTimeZone().getID().isNotEmpty())
            println(java.util.TimeZone.getDefault().getID().isNotEmpty())

            val gregorian = java.util.GregorianCalendar(java.util.TimeZone.getTimeZone("UTC"))
            gregorian.setTimeInMillis(0L)
            println(gregorian.get(java.util.Calendar.YEAR))

            println(java.util.Formatter().format("%d", 5).toString())

            val bits = java.util.BitSet().apply { set(1) }
            println(bits.get(1))
            println(bits.cardinality())

            val values = java.util.HashSet<Int>()
            values.add(7)
            println(values.contains(7))
            println(values.size)

            val function = java.util.function.Function<Int, Int> { it + 1 }
            println(function.apply(5))

            val logger = java.util.logging.Logger.getLogger("sample")
            println(logger.name)

            val uuid = java.util.UUID.fromString("00112233-4455-6677-8899-aabbccddeeff")
            println(uuid.toString())
            println(java.util.UUID.randomUUID().version() == 4)

            val latch = java.util.concurrent.CountDownLatch(1)
            val timer = java.util.Timer("sample")
            timer.schedule(object : java.util.TimerTask() {
                override fun run() {
                    latch.countDown()
                }
            }, 0L)
            println(latch.await(5L, java.util.concurrent.TimeUnit.SECONDS))
            timer.cancel()
        }
        """
        try withTemporaryFile(contents: source) { inputPath in
            for optLevel in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let context = try runCodegenPipeline(
                    inputPath: inputPath,
                    moduleName: "JavaUtilCompleteness_\(optLevel.rawValue)",
                    outputPath: outputPath,
                    optLevel: optLevel,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath
                )
                try assertNoDiagnosticErrors(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.exitCode == 0, "\(result.stderr)")
                #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            true
            true
            1970
            5
            true
            1
            true
            1
            6
            sample
            00112233-4455-6677-8899-aabbccddeeff
            true
            true

            """)
            }
        }
    }
}
