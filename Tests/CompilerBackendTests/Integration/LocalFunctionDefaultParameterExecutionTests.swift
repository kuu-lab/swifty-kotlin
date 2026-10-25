#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct LocalFunctionDefaultParameterExecutionTests {
    @Test(arguments: [true, false], [0, 2])
    func parameterDefaultCanReadEarlierLocalArgument(fromSource: Bool, optimization: Int) throws {
        let source = try diffCaseSource("local_function_default_parameter_dependency.kt", file: #filePath)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)

        let library = fromSource ? nil : try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: "KUU2265LocalDefaultParameter",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: fromSource,
            stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: !fromSource
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == "OK\nliteral!\nignoredexplicit\ntop\nmember\n")
        #expect(execution.stderr.isEmpty)
    }

    @Test
    func parameterDefaultCanReadGenericClassReceiver() throws {
        let source = try diffCaseSource("local_function_default_class_generic_char.kt", file: #filePath)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("consumer.kt").path
        let output = directory.appendingPathComponent("consumer").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)

        let library = try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: "KUU2951LocalDefaultGenericChar",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            includeStdlib: false,
            stdlibLibraryPath: library,
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let execution = try CommandRunner.run(executable: output, arguments: [])
        #expect(execution.exitCode == 0, "\(execution.stderr)")
        #expect(execution.stdout == "OK\n")
        #expect(execution.stderr.isEmpty)
    }
}
#endif
