@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct MutableMapIndexedAssignExtensionTests {
    @Test(arguments: [true, false], [0, 2])
    func unrelatedArraySetDoesNotHideMutableMapSet(fromSource: Bool, optimization: Int) throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = repository.appendingPathComponent(
            "Scripts/diff_cases/mutable_map_set_unrelated_array_extension.kt"
        ).path
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("map-set").path
        let options = CompilerOptions(
            moduleName: "MutableMapIndexedAssignExtension",
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
        #expect(result.stdout == "[1]\n", "fromSource=\(fromSource), O\(optimization)")
    }
}
