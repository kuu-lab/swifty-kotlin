@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-3648: stream callbacks stay lazy across generic and primitive pipelines.
    @Test
    func testNativeStreamLazinessAcrossSourceAndFreshArtifactAtO0O2() throws {
        let source = try diffCaseSource("java_util_stream_lazy_pipelines.kt", file: #filePath)
        let artifactPath = try Self.buildStdlibArtifact()
        let expected = """
        pipeline-before=0
        pipeline=[30]
        pipeline-events=peek1,map1,filter10,peek2,map2,filter20,peek3,map3,filter30
        exception-before=0
        exception-limited=1
        exception-after=thrown/3
        int-before=0
        int-sum=12
        int-after=3
        long-before=0
        long-sum=6
        long-after=3
        double-before=0
        double-sum=3.0
        double-after=3
        short-circuit=2/2
        boxed-before=0
        boxed=[65]/1
        mapToObj-before=0
        mapToObj=[v7]/1
        long-boxed-before=0
        long-boxed=[5]/1

        """

        for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] as [(String, String?)] {
            for optimizationLevel in [OptimizationLevel.O0, .O2] {
                let output = try runNativeStreamLazinessConsumer(
                    source,
                    moduleName: "KUU3648Stream_\(surface)_\(optimizationLevel.rawValue)",
                    stdlibLibraryPath: libraryPath,
                    optLevel: optimizationLevel
                )
                #expect(
                    output == expected,
                    "Unexpected output using \(surface) at \(optimizationLevel): \(String(reflecting: output))"
                )
            }
        }
    }
}

private func runNativeStreamLazinessConsumer(
    _ source: String,
    moduleName: String,
    stdlibLibraryPath: String?,
    optLevel: OptimizationLevel
) throws -> String {
    var output = ""
    try withTemporaryFile(contents: source) { inputPath in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .path
        defer {
            try? FileManager.default.removeItem(atPath: outputBase)
            try? FileManager.default.removeItem(atPath: outputBase + ".o")
        }

        let context = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [inputPath],
                outputPath: outputBase,
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

        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        guard result.exitCode == 0 else {
            throw TestCompilationFailure(
                description: "Execution failed with exit \(result.exitCode): \(result.stderr)"
            )
        }
        output = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
    }
    return output
}
