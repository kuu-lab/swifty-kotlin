@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ImportedConstLibraryExecutionTests {
    private func fixture() throws -> Data {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return try Data(contentsOf: root.appendingPathComponent(
            "Tests/CompilerCoreTests/Klib/Fixtures/ImportedConstants.kt"
        ))
    }

    @Test(arguments: [0, 2])
    func separatelyCompiledProducerExportsConstWithoutPromotingOrdinaryVal(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        let stdlib = try #require(CompilerOptions.defaultStdlibLibraryPath)
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let source = try fixture()
        let consumerSource = Data("""
        import nativeconstantproducer.*
        const val COPIED: Int = SIZE
        const val SWITCH: Boolean = ENABLED
        fun main() {
            println(COPIED)
            println(SWITCH)
            println(ordinary)
            println(ordinaryBoolean)
            println(mutableValue)
        }
        """.utf8)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at: directory) } }
        let producer = directory.appendingPathComponent("Producer.kt")
        try source.write(to: producer)
        let output = directory.appendingPathComponent("producer")
        let producerOptions = CompilerOptions(
            moduleName: "KUU1772ConstProducer", inputs: [producer.path], outputPath: output.path,
            emit: .library, target: TargetTriple.hostDefault(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: producerOptions))
        let artifact = output.appendingPathExtension("kklib")
        let records = MetadataDecoder().decode(try String(
            contentsOf: artifact.appendingPathComponent("metadata.bin"), encoding: .utf8
        ))
        let constant = try #require(records.first { $0.fqName == "nativeconstantproducer.SIZE" })
        let enabled = try #require(records.first { $0.fqName == "nativeconstantproducer.ENABLED" })
        try #require(constant.constValueLiteral == "i:8192")
        try #require(enabled.constValueLiteral == "b:1")
        for name in ["ordinary", "ordinaryBoolean", "mutableValue"] {
            let record = try #require(records.first { $0.fqName == "nativeconstantproducer." + name })
            try #require(record.constValueLiteral == nil)
        }
        let rejected = directory.appendingPathComponent("Rejected.kt")
        try "import nativeconstantproducer.ordinary\nconst val INVALID = ordinary\n"
            .write(to: rejected, atomically: true, encoding: .utf8)
        let negative = makeCompilationContext(
            inputs: [rejected.path], searchPaths: [artifact.path],
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        try runSema(negative)
        let errors = negative.diagnostics.diagnostics.filter { $0.severity == .error }
        try #require(errors.count == 1, "\(errors)")
        try #require(errors.first?.code == "KSWIFTK-SEMA-0083")
        let consumer = directory.appendingPathComponent("Consumer.kt")
        try consumerSource.write(to: consumer)
        let executable = directory.appendingPathComponent("consumer")
        let options = CompilerOptions(
            moduleName: "KUU1772ConstConsumer", inputs: [consumer.path], outputPath: executable.path,
            emit: .executable, searchPaths: [artifact.path], target: TargetTriple.hostDefault(),
            optLevel: level, stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: executable.path, arguments: [], timeout: 10)
        try Data(result.stdout.utf8).write(to: directory.appendingPathComponent("run.stdout"))
        try Data(result.stderr.utf8).write(to: directory.appendingPathComponent("run.stderr"))
        try #require(result.exitCode == 0, "\(result.stderr)")
        try #require(Data(result.stdout.utf8) == Data("8192\ntrue\n8192\ntrue\n8192\n".utf8))
        try #require(try Data(contentsOf: producer) == source)
        try #require(try Data(contentsOf: consumer) == consumerSource)
        completed = true
    }
}
