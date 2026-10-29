@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct InterpreterContextIdentifierTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test(arguments: [true, false], [0, 2])
    func interpreterMapWritesPreserveOrdinaryContextNames(fromSource: Bool, optimization: Int) throws {
        let input = repository.appendingPathComponent(
            "Scripts/diff_cases/interpreter_context_parameter_map.kt"
        ).path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("interpreter").path
        let options = CompilerOptions(
            moduleName: "InterpreterContextIdentifier",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stderr.isEmpty, "fromSource=\(fromSource), O\(optimization): \(result.stderr)")
        #expect(result.stdout == """
        x=10
        y=20
        sum=30
        d=5
        result=150
        override=17
        ctx=19
        local=23
        named=42

        """, "fromSource=\(fromSource), O\(optimization)")
    }
}
