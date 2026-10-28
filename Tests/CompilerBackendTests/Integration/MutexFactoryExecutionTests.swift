@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct MutexFactoryExecutionTests {
    private let expectedOutput = "false\ntrue\nfalse\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\nowner-mismatch\ntrue\ntrue\nrelease\nacquired\nfalse\n"

    @Test(arguments: [false, true], [0, 2])
    func initialStateFromSourceAndStdlibLibrary(fromSource: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("mutex_initial_locked.kt", file: #filePath),
            expectedOutput: expectedOutput,
            moduleName: "KUU2055MutexFactory",
            allowDefaultStdlibLibrary: !fromSource,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }

    @Test(arguments: [0, 2])
    func initialStateAcrossIndependentProducerConsumer(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let stdlib = try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let producerInput = directory.appendingPathComponent("producer.kt").path
        let producer = directory.appendingPathComponent("MutexFactoryProducer").path
        let source = try diffCaseSource("mutex_initial_locked.kt", file: #filePath)
        try ("package mutexfactory\n" + source.replacingOccurrences(of: "fun main()", with: "fun verifyMutexFactory()"))
            .write(toFile: producerInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "MutexFactoryProducer", inputs: [producerInput], outputPath: producer, emit: .library,
            target: defaultTargetTriple(), optLevel: level, stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: false
        )))
        // Remove the producer source so only its serialized library crosses the boundary.
        try FileManager.default.removeItem(atPath: producerInput)

        let consumerInput = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try "import mutexfactory.verifyMutexFactory\nfun main() { verifyMutexFactory() }\n"
            .write(toFile: consumerInput, atomically: true, encoding: .utf8)
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "MutexFactoryConsumer", inputs: [consumerInput], outputPath: output, emit: .executable,
            searchPaths: [producer + ".kklib"], target: defaultTargetTriple(), optLevel: level,
            stdlibLibraryPath: stdlib, allowDefaultStdlibLibrary: false
        )))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == expectedOutput)
        #expect(result.stderr.isEmpty)
    }
}
