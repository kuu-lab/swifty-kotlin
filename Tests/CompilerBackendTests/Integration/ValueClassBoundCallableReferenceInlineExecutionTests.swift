import Foundation
@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import TestStdlibCache
import Testing

@Suite(.serialized)
struct ValueClassBoundCallableReferenceInlineExecutionTests {
    @Test(arguments: [0, 2])
    func boundValueClassMethodReferencesExecuteThroughInlineFunction(optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try diffCaseSource(
            "kuu_3410_value_class_bound_callable_reference_inline.kt",
            file: #filePath
        )
        let input = directory.appendingPathComponent("bound_reference.kt").path
        let output = directory.appendingPathComponent("bound_reference").path
        try source.write(toFile: input, atomically: true, encoding: .utf8)

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: CompilerOptions(
            moduleName: "KUU3410ValueClassBoundReferenceInline",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            stdlibLibraryPath: try testStdlibArtifactPath()
        )))

        let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
        #expect(result.exitCode == 0, "unexpected stderr: \(result.stderr)")
        #expect(result.stdout == "0\n1\n2\n3\n4\n5\n6\n7\n")
    }
}
