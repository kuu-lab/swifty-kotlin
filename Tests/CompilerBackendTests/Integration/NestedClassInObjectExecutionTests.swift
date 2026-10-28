@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct NestedClassInObjectExecutionTests {
    private let expectedOutput = "OK\n1\n"

    @Test(arguments: [false, true], [0, 2])
    func enclosingSingletonCallsRunWithDefaultAndExplicitStdlibs(
        useExplicitStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        let source = try diffCaseSource("kuu_2321_nested_class_in_object.kt")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.kt").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("program").path

        let stdlib = useExplicitStdlibLibrary ? try testStdlibArtifactPath() : nil
        let result = makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "NestedClassInObjectO\(optimization)",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: stdlib,
            allowDefaultStdlibLibrary: true
        ))

        let mode = useExplicitStdlibLibrary ? "explicit fresh .kklib" : "default stdlib artifact"
        try assertCompilationSucceeded(result, context: "\(mode), O\(optimization)")
        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "Execution stderr: \(execution.stderr)")
        #expect(execution.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expectedOutput)
    }
}
