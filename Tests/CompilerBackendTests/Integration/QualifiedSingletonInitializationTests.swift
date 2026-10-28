@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct QualifiedSingletonInitializationTests {
    @Test(arguments: ["source", "stdlib-library", "producer-consumer"], [0, 2])
    func qualifiedValuesInitializeBeforePassingTheReceiver(route: String, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = route == "source" ? nil : try testStdlibArtifactPath()
        let producer = """
        package qualifiedinit
        private var events = ""
        private fun record(label: String): String { events += label; return label }
        object Qualified { val value = record("Q") }
        object Imported { val value = record("I") }
        class Holder { companion object Named { val value = record("C") } }
        object Constants {
            const val VALUE = 7
            init { record("X") }
        }
        fun history(): String = events
        """
        let consumer = """
        package qualifiedconsumer
        import qualifiedinit.*
        import kotlin.io.encoding.Base64
        import kotlinx.coroutines.NonCancellable
        import kotlinx.io.bytestring.*
        private fun observe(value: Any, kind: Int) {
            println(history())
            println(when (kind) {
                0 -> value === Qualified
                1 -> value === Imported
                else -> value === Holder.Named
            })
        }
        fun main() {
            println(kotlin.io.encoding.Base64.encode(ByteString(1, 2, 3), 0, 2))
            println(kotlin.io.encoding.Base64.encode(ByteString(1, 2, 3)))
            println(Base64.encode(ByteString(1, 2, 3), 0, 2))
            observe(qualifiedinit.Qualified, 0)
            observe(Imported, 1)
            observe(qualifiedinit.Holder, 2)
            println(qualifiedinit.Constants.VALUE)
            println(history())
            observe(qualifiedinit.Qualified, 0)
            observe(qualifiedinit.Holder.Named, 2)
            println(kotlinx.coroutines.NonCancellable === NonCancellable)
            println(kotlin.Unit === Unit)
        }
        """
        let expected = "AQI=\nAQID\nAQI=\nQ\ntrue\nQI\ntrue\nQIC\ntrue\n7\nQIC\nQIC\ntrue\nQIC\ntrue\ntrue\ntrue\n"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let producerPath = directory.appendingPathComponent("Producer.kt").path
        let consumerPath = directory.appendingPathComponent("Consumer.kt").path
        try producer.write(toFile: producerPath, atomically: true, encoding: .utf8)
        try consumer.write(toFile: consumerPath, atomically: true, encoding: .utf8)
        let libraryBase = directory.appendingPathComponent("Producer").path
        if route == "producer-consumer" {
            let options = CompilerOptions(
                moduleName: "QualifiedProducer", inputs: [producerPath], outputPath: libraryBase,
                emit: .library, target: defaultTargetTriple(), optLevel: level,
                stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            try FileManager.default.moveItem(atPath: producerPath, toPath: producerPath + ".evidence")
        }
        let binary = directory.appendingPathComponent("consumer").path
        let options = CompilerOptions(
            moduleName: "QualifiedConsumer",
            inputs: route == "producer-consumer" ? [consumerPath] : [producerPath, consumerPath],
            outputPath: binary, emit: .executable,
            searchPaths: route == "producer-consumer" ? [libraryBase + ".kklib"] : [],
            target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false,
            entryPointFQName: "qualifiedconsumer.main"
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: binary, arguments: [])
        #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == expected)
    }
}
