import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct JavaLangIntegerMinTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture() throws -> String {
        try String(
            contentsOf: repository.appendingPathComponent("Scripts/diff_cases/levenshtein_length_algorithm.kt"),
            encoding: .utf8
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func integerMinStaticImportWorksForSourceAndLibrary(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("levenshtein.kt").path
        let output = directory.appendingPathComponent("levenshtein").path
        try fixture().write(toFile: input, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU1908",
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
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "2\n3\n-2147483648\n-2147483648\n-2147483648\n2147483647\n3\n3\n3\n0\n")
        #expect(result.stderr.isEmpty, "\(result.stderr)")
    }
}
