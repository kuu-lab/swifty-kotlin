@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3055: Java array helpers bind and execute through source and artifact stdlib paths.
    @Test
    func testJavaUtilArraysThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let source = try diffCaseSource("java_util_arrays.kt", file: #filePath)
        let expected = try diffCaseSource("java_util_arrays.expected", file: #filePath)
        let artifactPath = try Self.buildStdlibArtifact()

        for libraryPath in [nil, artifactPath] {
            for optLevel in [OptimizationLevel.O0, .O2] {
                let output = try runJavaUtilArraysConsumer(
                    source,
                    moduleName: "KUU3055Arrays_\(libraryPath == nil ? "Source" : "Artifact")_\(optLevel)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optLevel
                )
                #expect(output == expected, "Unexpected output for source: \(libraryPath == nil), optimization: \(optLevel)")
            }
        }
    }
}

private func runJavaUtilArraysConsumer(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
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
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
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
