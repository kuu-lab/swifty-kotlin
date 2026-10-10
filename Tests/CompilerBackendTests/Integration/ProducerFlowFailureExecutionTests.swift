import Foundation
@testable import CompilerBackend
@testable import CompilerCore
import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ProducerFlowFailureExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/kotlinx_coroutines_flow_producer_failures.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func producerFailuresAndCleanupMatchPublishedCoroutines(fromSource: Bool, optimization: Int) throws {
        try withDirectory { directory in
            let input = directory.appendingPathComponent("flow.kt").path
            let output = directory.appendingPathComponent("flow").path
            try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "ProducerFlowFailures", inputs: [input], outputPath: output, emit: .executable,
                target: defaultTargetTriple(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(), allowDefaultStdlibLibrary: !fromSource
            )))
            try expectFixtureOutput(output)
        }
    }

    @Test(arguments: [0, 2])
    func separateLibraryPreservesProducerFailureAndCapture(optimization: Int) throws {
        try withDirectory { directory in
            let stdlib = try testStdlibArtifactPath()
            let level = try #require(OptimizationLevel(rawValue: optimization))
            let source = try fixture("kt")
            let boundary = try #require(source.range(of: "fun main() = runBlocking {"))
            let producer = directory.appendingPathComponent("producer.kt").path
            let library = directory.appendingPathComponent("FlowProducer").path
            try ("package producer\n" + String(source[..<boundary.lowerBound]))
                .write(toFile: producer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "FlowProducer", inputs: [producer], outputPath: library, emit: .library,
                target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            )))
            let consumer = directory.appendingPathComponent("consumer.kt").path
            let output = directory.appendingPathComponent("consumer").path
            let consumerMain = String(source[boundary.lowerBound...])
            try ("import producer.*\nimport kotlinx.coroutines.*\nimport kotlinx.coroutines.flow.*\nimport kotlinx.coroutines.channels.*\n"
                + consumerMain).write(toFile: consumer, atomically: true, encoding: .utf8)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "FlowConsumer", inputs: [consumer], outputPath: output, emit: .executable,
                searchPaths: [library + ".kklib"], target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib
            )))
            try expectFixtureOutput(output)
        }
    }

    private func expectFixtureOutput(_ output: String) throws {
        let result = try CommandRunner.run(executable: output, arguments: [], timeout: 30)
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == (try fixture("expected")))
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
