#if canImport(Testing)
import Foundation
import Testing

@Suite struct DiffKotlincRegressionCasesTests {
    @Test func testDiffKotlincRegressionCasesAreTracked() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let casesDir = root.appendingPathComponent("Scripts/diff_cases", isDirectory: true)
        let readmePath = casesDir.appendingPathComponent("README.md").path

        #expect(FileManager.default.fileExists(atPath: readmePath))

        let files = try FileManager.default.contentsOfDirectory(at: casesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(files.count >= 13)

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(!(contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), "Empty case file: \(file.lastPathComponent)")
            let isScript = file.lastPathComponent.hasPrefix("script_")
            if !isScript {
                #expect(
                    contents.contains("fun ") || contents.contains("class ") || contents.contains("object "),
                    "Regression case should include a top-level declaration: \(file.lastPathComponent)"
                )
            }
        }
    }
}
#endif
