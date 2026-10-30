@testable import CompilerCore
import Foundation
import Testing

@Suite(.serialized)
struct CapturedMemberMethodRangePredicateTests {
    @Test(arguments: [true, false], [0, 2])
    func capturedLongPredicateReturnsTheSameValue(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        let source = try diffCaseSource(
            "kuu_1862_member_method_captured_long_range_predicate.kt",
            file: #filePath
        )
        try source.write(toFile: input, atomically: true, encoding: .utf8)

        let level = try #require(OptimizationLevel(rawValue: optimization))
        let stdlibLibraryPath = fromSource ? nil : try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: "KUU1862CapturedRangePredicate",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: level,
            includeStdlib: fromSource,
            stdlibLibraryPath: stdlibLibraryPath,
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == "4\n[4]\n288\n71503\n")
    }
}
