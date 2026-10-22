@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-2794: java.util.ArrayDeque imports and Java deque members work from the shared stdlib artifact.
    @Test
    func testJavaUtilArrayDequeThroughSharedStdlibArtifact() throws {
        let source = try diffCaseSource("java_util_array_deque.kt", file: #filePath)
        let expected = """
        2
        3
        2
        3
        true
        true
        [1, 2, 3, 4]
        1
        4
        [2, 3]
        true
        2
        true
        true
        5 6 6
        4 6
        7

        """
        let artifactPath = try testStdlibArtifactPath()
        let output = try runJavaUtilArrayDequeConsumer(
            source,
            moduleName: "KUU2794ArrayDeque",
            stdlibLibraryPath: artifactPath
        )
        #expect(output == expected, "Unexpected ArrayDeque output: \(String(reflecting: output))")
    }
}

private func runJavaUtilArrayDequeConsumer(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputPath)
            try? FileManager.default.removeItem(atPath: outputPath + ".o")
        }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: .O0,
                includeStdlib: false,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            ),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(context)
        try assertNoDiagnosticErrors(context)
        try LoweringPhase().run(context)
        try CodegenPhase().run(context)
        try LinkPhase().run(context)

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        guard result.exitCode == 0 else {
            throw TestCompilationFailure(
                description: "Execution failed with exit \(result.exitCode): \(result.stderr)"
            )
        }
        output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return output
}
