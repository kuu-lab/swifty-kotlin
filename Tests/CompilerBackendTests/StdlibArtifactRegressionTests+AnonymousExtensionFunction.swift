@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2192: Anonymous extension function expressions `fun Int.(): String`
    /// should resolve properly as function types with receiver and emit callback ABI.
    @Test
    func testAnonymousExtensionFunctionAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let minimalPath = repoRoot.appendingPathComponent(
            "Scripts/diff_cases/anonymous_extension_function_probe.kt"
        ).path
        let originalPath = repoRoot.appendingPathComponent(
            "Scripts/diff_cases/extension_function_fake_override.kt"
        ).path
        let controlPath = repoRoot.appendingPathComponent(
            "Scripts/diff_cases/receiver_lambda_probe.kt"
        ).path

        let minimalSource = try String(contentsOfFile: minimalPath, encoding: .utf8)
        let originalSource = try String(contentsOfFile: originalPath, encoding: .utf8)
        let controlSource = try String(contentsOfFile: controlPath, encoding: .utf8)

        let artifactPath = try Self.buildStdlibArtifact()

        // 1. Minimal and original fixtures across source and fresh .kklib × O0 / O2
        for (caseName, source) in [("minimal", minimalSource), ("original", originalSource)] {
            for (surface, libraryPath) in [("source", nil), ("fresh .kklib", artifactPath)] {
                for optimization in [OptimizationLevel.O0, .O2] {
                    let output = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: output) }
                    try withTemporaryFile(contents: source) { input in
                        let options = CompilerOptions(
                            moduleName: "KUU2192_\(caseName)_\(surface)_\(optimization.rawValue)",
                            inputs: [input],
                            outputPath: output,
                            emit: .executable,
                            target: defaultTargetTriple(),
                            optLevel: optimization,
                            includeStdlib: libraryPath == nil,
                            stdlibLibraryPath: libraryPath,
                            allowDefaultStdlibLibrary: false
                        )
                        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
                    }
                    let result = try CommandRunner.run(executable: output, arguments: [])
                    #expect(result.exitCode == 0, "\(caseName) on \(surface) at \(optimization): \(result.stderr)")
                    #expect(result.stderr.isEmpty, "\(caseName) on \(surface) at \(optimization)")
                    #expect(result.stdout == "OK\n", "\(caseName) on \(surface) at \(optimization)")
                }
            }
        }

        // 2. Control (receiver lambda) fixture on fresh .kklib × O0 / O2
        for optimization in [OptimizationLevel.O0, .O2] {
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }
            try withTemporaryFile(contents: controlSource) { input in
                let options = CompilerOptions(
                    moduleName: "KUU2192_control_fresh_\(optimization.rawValue)",
                    inputs: [input],
                    outputPath: output,
                    emit: .executable,
                    target: defaultTargetTriple(),
                    optLevel: optimization,
                    includeStdlib: false,
                    stdlibLibraryPath: artifactPath,
                    allowDefaultStdlibLibrary: false
                )
                try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            }
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "control on fresh .kklib at \(optimization): \(result.stderr)")
            #expect(result.stderr.isEmpty, "control on fresh .kklib at \(optimization)")
            #expect(result.stdout == "OK\n", "control on fresh .kklib at \(optimization)")
        }
    }
}
