#if canImport(Testing)
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct IOUnsafeByteStringOperationsSingletonTests {
    @Test(arguments: ["source", "stdlib-library", "producer-consumer"], [0, 2])
    func externalConsumerObservesOneUnsafeOperationsSingleton(route: String, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlib = route == "source" ? nil : try testStdlibArtifactPath()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let producer = """
        @file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

        package kuu2582.producer

        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        fun exportedSingleton(): Any = UnsafeByteStringOperations
        """
        let producerImport = route == "producer-consumer"
            ? "import kuu2582.producer.exportedSingleton\n"
            : ""
        let producerChecks = route == "producer-consumer"
            ? """
                val imported: Any = exportedSingleton()
                println(typed === imported)
                println(imported === exportedSingleton())
            """
            : ""
        let consumer = """
        @file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

        package kuu2582.consumer

        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
        \(producerImport)

        fun main() {
            val typed: UnsafeByteStringOperations = UnsafeByteStringOperations
            val erased: Any = UnsafeByteStringOperations
            println(typed === erased)
            println(typed === UnsafeByteStringOperations)
        \(producerChecks)
        }
        """

        let producerPath = directory.appendingPathComponent("Producer.kt").path
        let consumerPath = directory.appendingPathComponent("Consumer.kt").path
        try producer.write(toFile: producerPath, atomically: true, encoding: .utf8)
        try consumer.write(toFile: consumerPath, atomically: true, encoding: .utf8)

        let compiler = makeTestDriver()
        let producerLibraryBase = directory.appendingPathComponent("UnsafeOperationsProducer").path
        if route == "producer-consumer" {
            let producerOptions = CompilerOptions(
                moduleName: "KUU2582UnsafeOperationsProducer",
                inputs: [producerPath],
                outputPath: producerLibraryBase,
                emit: .library,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: level,
                stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(compiler.runForTesting(options: producerOptions))
            try FileManager.default.moveItem(atPath: producerPath, toPath: producerPath + ".evidence")
        }

        let output = directory.appendingPathComponent("consumer").path
        let options = CompilerOptions(
            moduleName: "KUU2582UnsafeOperationsConsumer",
            inputs: [consumerPath],
            outputPath: output,
            emit: .executable,
            searchPaths: route == "producer-consumer" ? [producerLibraryBase + ".kklib"] : [],
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: level,
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false,
            entryPointFQName: "kuu2582.consumer.main"
        )
        try assertCompilationSucceeded(compiler.runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(route) O\(optimization): \(result.stderr)")
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == (route == "producer-consumer" ? "true\ntrue\ntrue\ntrue\n" : "true\ntrue\n"))
    }
}
#endif
