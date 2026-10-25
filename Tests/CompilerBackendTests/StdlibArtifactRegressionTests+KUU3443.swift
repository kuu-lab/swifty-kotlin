@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3443: Java functional interfaces, streams, and primitive optionals are bundled APIs.
    @Test
    func testJavaUtilFunctionsStreamsAndPrimitiveOptionals() throws {
        let artifactDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: artifactDirectory) }
        let artifactPath = try Self.buildKUU3443StdlibArtifact(
            outputPath: artifactDirectory.appendingPathComponent("KSwiftKStdlib").path
        )
        let source = try diffCaseSource("java_util_function_stream_optionals.kt", file: #filePath)
        let expected = "6\ntrue\n7\n6\npair:9\n2\n2,4,6\n6\n6\n6\n5\n2,3,4\n2,4,6\nvalue\n5\n9\n5\n8\n2.5\n"

        try withTemporaryFile(contents: source) { inputPath in
            for level in [OptimizationLevel.O0, .O2] {
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: outputPath) }
                let context = try runCodegenPipeline(
                    inputPath: inputPath,
                    moduleName: "KUU3443JavaUtilStreams",
                    outputPath: outputPath,
                    optLevel: level,
                    allowDefaultStdlibLibrary: false,
                    stdlibLibraryPath: artifactPath
                )
                let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
                if !errors.isEmpty {
                    let details = errors.map { diagnostic in
                        guard let range = diagnostic.primaryRange else { return String(describing: diagnostic) }
                        let location = context.sourceManager.lineColumn(of: range.start)
                        let path = context.sourceManager.path(of: range.start.file)
                        return "\(path):\(location.line):\(location.column): \(diagnostic)"
                    }.joined(separator: "\n")
                    throw CompilerPipelineError.invalidInput("Unexpected KUU-3443 diagnostics:\n\(details)")
                }
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: outputPath, arguments: [])
                #expect(result.exitCode == 0, "\(level): \(result.stderr)")
                #expect(result.stderr.isEmpty)
                #expect(result.stdout == expected, "\(level): \(result.stdout)")
            }
        }
    }

    private static func buildKUU3443StdlibArtifact(outputPath: String) throws -> String {
        let context = CompilerTestSupport.makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: outputPath,
            includeStdlib: true,
            stdlibOnly: true,
            allowDefaultStdlibLibrary: false
        )

        do {
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
        } catch {
            let diagnostics = context.diagnostics.diagnostics.map { diagnostic in
                guard let range = diagnostic.primaryRange else { return String(describing: diagnostic) }
                let location = context.sourceManager.lineColumn(of: range.start)
                let path = context.sourceManager.path(of: range.start.file)
                return "\(path):\(location.line):\(location.column): \(diagnostic)"
            }.joined(separator: "\n")
            throw CompilerPipelineError.invalidInput(
                "KUU-3443 fresh stdlib artifact build failed: \(error)\n\(diagnostics)"
            )
        }

        return outputPath + ".kklib"
    }
}
