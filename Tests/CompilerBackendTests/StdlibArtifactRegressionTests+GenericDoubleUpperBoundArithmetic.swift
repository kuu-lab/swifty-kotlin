#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2656: arithmetic on a type parameter bounded by Double keeps the
    /// floating-point representation through operator lowering and ABI unboxing.
    @Test
    func testGenericDoubleUpperBoundArithmetic() throws {
        let source = try diffCaseSource("generic_double_upper_bound_arithmetic.kt", file: #filePath)
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let context = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GenericDoubleUpperBoundArithmetic",
                outputPath: output
            )
            try assertNoDiagnosticErrors(context)
            try LinkPhase().run(context)
            let result = try CommandRunner.run(executable: output, arguments: [], timeout: 10)
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "4.0\n2.0\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
