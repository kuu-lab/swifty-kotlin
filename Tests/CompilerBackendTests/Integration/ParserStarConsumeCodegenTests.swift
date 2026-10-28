import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct ParserStarConsumeCodegenTests {
    private static let artifactLock = NSLock()
    private static nonisolated(unsafe) var artifactPath: String?

    private static func freshArtifact() throws -> String {
        artifactLock.lock()
        defer { artifactLock.unlock() }
        if let artifactPath { return artifactPath }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let path = try StdlibArtifactBuilder.build(outputBase: output, target: TargetTriple.hostDefault())
        artifactPath = path
        print("Parser consume stdlib artifact: \(path)")
        return path
    }

    @Test(arguments: [false, true], [0, 2])
    func twoStageMapMatchesReference(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = fromSource ? nil : try Self.freshArtifact()
        let fixture = repository.appendingPathComponent("Tests/CompilerBackendTests/Fixtures/parser_star_consume")
        let originals = ["ParserResult.kt", "Parser.kt", "Map.kt", "Consumer.kt", "Main.kt"]
            .map { fixture.appendingPathComponent($0).path }
        let concatenated = repository.appendingPathComponent("Scripts/diff_cases/parser_star_consume_two_stage_map.kt").path
        for (index, inputs) in [originals, [concatenated]].enumerated() {
            let output = directory.appendingPathComponent("consumer\(index)").path
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
                moduleName: "ParserConsumer", inputs: inputs, outputPath: output, emit: .executable,
                target: TargetTriple.hostDefault(), optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: !fromSource
            )))
            let execution = try CommandRunner.run(executable: output, arguments: [])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "Success(value=kotlin.Unit, remaining=tail)\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
