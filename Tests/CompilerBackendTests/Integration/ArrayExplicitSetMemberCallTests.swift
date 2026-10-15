#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ArrayExplicitSetMemberCallTests {
    private enum StdlibMode {
        case sourceInjection
        case defaultArtifact
        case freshArtifact

        var label: String {
            switch self {
            case .sourceInjection: "source injection"
            case .defaultArtifact: "default artifact"
            case .freshArtifact: "fresh artifact"
            }
        }
    }

    private func assertSetCalls(using stdlibMode: StdlibMode, optimization: Int) throws {
        let artifactPath: String?
        let allowDefaultStdlibLibrary: Bool
        switch stdlibMode {
        case .sourceInjection:
            artifactPath = nil
            allowDefaultStdlibLibrary = false
        case .defaultArtifact:
            _ = try testStdlibArtifactPath()
            artifactPath = nil
            allowDefaultStdlibLibrary = true
        case .freshArtifact:
            artifactPath = try StdlibArtifactRegressionTests.buildStdlibArtifact()
            allowDefaultStdlibLibrary = false
        }
        let source = try diffCaseSource("array_explicit_set.kt", file: #filePath)
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let optLevel = try #require(OptimizationLevel(rawValue: optimization))
            let ctx = try runCodegenPipeline(
                inputPath: inputPath,
                moduleName: "ArrayExplicitSet",
                outputPath: outputPath,
                optLevel: optLevel,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                stdlibLibraryPath: artifactPath
            )
            try assertNoDiagnosticErrors(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            let lane = "stdlib \(stdlibMode.label), O\(optimization)"
            #expect(result.exitCode == 0, "\(lane): \(result.stderr)")
            #expect(result.stderr.isEmpty, "\(lane): \(result.stderr)")
            #expect(result.stdout == "OK\nindexed:7\nx\nrivs:9\n", Comment(rawValue: lane))
        }
    }

    @Test
    func sourceO0() throws {
        try assertSetCalls(using: .sourceInjection, optimization: 0)
    }

    // Source-mode O2 IR also exposes a separate function-object arity failure tracked by KUU-2241.
    @Test
    func sourceO2KIRResolvesSetCalls() throws {
        let source = try diffCaseSource("array_explicit_set.kt", file: #filePath)
        try withTemporaryFile(contents: source) { inputPath in
            let options = CompilerOptions(
                moduleName: "ArrayExplicitSet",
                inputs: [inputPath],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: .O2,
                stdlibLibraryPath: nil,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try assertNoDiagnosticErrors(ctx)
            #expect(ctx.kir != nil)
        }
    }

    @Test
    func defaultStdlibO0() throws {
        try assertSetCalls(using: .defaultArtifact, optimization: 0)
    }

    @Test
    func defaultStdlibO2() throws {
        try assertSetCalls(using: .defaultArtifact, optimization: 2)
    }

    @Test
    func freshStdlibArtifactO0() throws {
        try assertSetCalls(using: .freshArtifact, optimization: 0)
    }

    @Test
    func freshStdlibArtifactO2() throws {
        try assertSetCalls(using: .freshArtifact, optimization: 2)
    }
}
#endif
