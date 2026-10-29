@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2189: Java Class rendering must preserve JVM names across stdlib modes.
    @Test
    func testJavaClassToStringAcrossStdlibSurfaces() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = [
            "any_java_class_tostring",
            "java_class_name_mapping",
            "kotlin_in_action_collections_java_class",
        ]
        let artifactPath = try Self.buildStdlibArtifact()

        for caseName in cases {
            let casePath = repoRoot.appendingPathComponent("Scripts/diff_cases/\(caseName).kt")
            let expected = try String(
                contentsOf: repoRoot.appendingPathComponent("Scripts/diff_cases/\(caseName).expected"),
                encoding: .utf8
            )
            let configurations: [(surface: String, libraryPath: String?, optLevels: [OptimizationLevel])] = [
                ("source", nil, [.O0, .O2]),
                ("artifact", artifactPath, [.O0, .O2]),
            ]
            for (surface, libraryPath, optLevels) in configurations {
                for optLevel in optLevels {
                    let outputBase = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).path
                    defer { try? FileManager.default.removeItem(atPath: outputBase) }
                    let context = try runCodegenPipeline(
                        inputPath: casePath.path,
                        moduleName: "KUU2189JavaClassToString",
                        outputPath: outputBase,
                        optLevel: optLevel,
                        allowDefaultStdlibLibrary: false,
                        stdlibLibraryPath: libraryPath
                    )
                    try assertNoDiagnosticErrors(context)
                    try LinkPhase().run(context)
                    let result = try CommandRunner.run(executable: outputBase, arguments: [])
                    let route = "\(caseName), \(surface), \(optLevel)"
                    #expect(result.exitCode == 0, "\(route): \(result.stderr)")
                    #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected, "\(route)")
                }
            }
        }
    }
}
