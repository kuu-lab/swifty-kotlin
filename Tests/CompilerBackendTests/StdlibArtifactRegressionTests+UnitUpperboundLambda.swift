#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {
    /// KUU-2203: a Unit upper bound enables lambda return coercion on both stdlib paths.
    @Test(arguments: [false, true], [0, 2])
    func testUnitUpperboundLambdaReturnType(useArtifact: Bool, optimization: Int) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = try diffCaseSource("unit_upperbound_lambda_return_type.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let context = try runCodegenPipeline(
                inputPath: path,
                moduleName: "UnitUpperboundLambdaReturnType",
                outputPath: output,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
