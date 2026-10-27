@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendReifiedNullableTypeChecksTests {
    @Test(arguments: [true, false], [0, 2])
    func nullableReifiedChecksPreserveNominalIdentity(fromSource: Bool, optimization: Int) throws {
        let source = try diffCaseSource("reified_nullable_type_checks.kt", file: #filePath)
        let stdlib = fromSource ? nil : try testStdlibArtifactPath()
        let level = try #require(OptimizationLevel(rawValue: optimization))
        let expected = """
        checks
        true
        true
        true
        true
        false
        false
        true
        true
        true
        true
        false
        false
        true
        forwarded
        true
        true
        false
        true
        captured
        true
        true
        false
        casts
        true
        true
        true
        true
        caught
        """ + "\n"

        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let options = CompilerOptions(
                moduleName: "ReifiedNullableTypeChecks",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: level,
                includeStdlib: fromSource,
                stdlibLibraryPath: stdlib,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "KUU-3610 source=\(fromSource) O\(optimization)"
            )

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == expected)
        }
    }
}
