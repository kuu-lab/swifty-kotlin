#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct GenericValueClassAnyBackingIsCheckTests {
    @Test(arguments: [0, 2])
    func genericAnyBackingPreservesRuntimeTypeChecks(optimization: Int) throws {
        let source = "annotation class JvmInline\n\n"
            + (try diffCaseSource("kuu_3411_generic_value_class_any_check.kt", file: #filePath))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("generic-value-class-any-check.kt")
        let output = directory.appendingPathComponent("generic-value-class-any-check")
        try source.write(to: input, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "KUU3411GenericValueClassAnyCheck",
            inputs: [input.path],
            outputPath: output.path,
            emit: .executable,
            target: TargetTriple.hostDefault(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(executable: output.path, arguments: [], timeout: 10)
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout.isEmpty)
        #expect(execution.stderr.isEmpty)
    }
}
#endif
