@testable import CompilerCore
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func javaUtilStackMatchesItsJvmContract(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("stack.kt").path
        let output = directory.appendingPathComponent("stack").path
        try diffCaseSource("kuu_1898_java_util_stack.kt", file: #filePath).write(
            toFile: input, atomically: true, encoding: .utf8
        )

        let options = CompilerOptions(
            moduleName: "KUU1898JavaUtilStack",
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
        #expect(result.stdout == "b\na\n1\nfalse\na\ntrue\npop:empty\npeek:empty\n2\n1\n0\n")
    }
}
