@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {

    /// KUU-2362: java.lang.Runtime CPU and memory APIs work through both bundled stdlib surfaces.
    @Test
    func testAvailableProcessorsAcrossStdlibSurfaces() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_runtime_available_processors.kt", file: #filePath)

        let surfaces: [(name: String, libraryPath: String?, optimizationLevels: [OptimizationLevel])] = [
            ("source", nil, [.O0, .O2]),
            ("fresh .kklib", artifactPath, [.O0, .O2]),
        ]

        for (surface, libraryPath, optimizationLevels) in surfaces {
            for optimizationLevel in optimizationLevels {
                try withTemporaryFile(contents: source) { userPath in
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }

                    let context = CompilationContext(
                        options: CompilerOptions(
                            moduleName: "KUU2362Runtime_\(surface)_\(optimizationLevel.rawValue)",
                            inputs: [userPath],
                            outputPath: outputBase,
                            emit: .executable,
                            target: defaultTargetTriple(),
                            optLevel: optimizationLevel,
                            includeStdlib: libraryPath == nil,
                            stdlibLibraryPath: libraryPath,
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
                    #expect(
                        result.exitCode == 0,
                        "Execution failed through \(surface) at \(optimizationLevel): \(result.stderr)"
                    )
                    #expect(
                        result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\n",
                        "Unexpected output through \(surface) at \(optimizationLevel): \(String(reflecting: result.stdout))"
                    )
                }
            }
        }
    }
}
