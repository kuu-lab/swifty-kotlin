import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct AnonymousFunctionExpectedTypeExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture(_ suffix: String) throws -> String {
        try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/kuu_2199_anonymous_function_expected_type.\(suffix)"), encoding: .utf8)
    }

    @Test(arguments: [false, true], [0, 2])
    func expectedParameterTypesAndAnonymousReturnsMatchKotlin(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("anonymous_function.kt").path
        let output = directory.appendingPathComponent("anonymous_function").path
        try fixture("kt").write(toFile: input, atomically: true, encoding: .utf8)
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "AnonymousFunctionExpectedType",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: level,
            includeStdlib: fromSource,
            stdlibLibraryPath: fromSource ? nil : try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: !fromSource
        )))

        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "Alice\nAlice\nAlice\nAlice\nAlice\nAlice\nBob is not Alice\nFinished\n")
    }
}
