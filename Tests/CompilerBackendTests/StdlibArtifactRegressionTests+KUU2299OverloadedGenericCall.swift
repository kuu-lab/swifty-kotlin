#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2299: outer expected result types contextualize returned lambdas
    /// through top-level and receiver-extension generic overloads.
    @Test(arguments: [false, true], [0, 2])
    func testOverloadedGenericCallPropagatesExpectedResultToNestedLambda(
        useArtifact: Bool,
        optimization: Int
    ) throws {
        let optLevel: OptimizationLevel = optimization == 0 ? .O0 : .O2
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let source = try diffCaseSource("kuu_2299_overloaded_generic_call_implicit_it.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let context = try runCodegenPipeline(
                inputPath: path,
                moduleName: "KUU2299OverloadedGenericCall",
                outputPath: output,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "OK\nOK\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
