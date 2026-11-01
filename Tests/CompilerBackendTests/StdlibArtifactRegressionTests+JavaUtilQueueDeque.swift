@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3869: bundled java.util Queue/Deque-family shims declare `E?`
    /// where the JVM signature is the unannotated `E`. Kotlin/JVM resolves
    /// the call-site result as the flexible platform type `E!`, so bare
    /// member calls, non-null targets, and `K`-parameter arguments are legal
    /// while empty results still produce a real null (NPE on unchecked
    /// non-null use). Pinned through bundled-source injection and a freshly
    /// generated `.kklib` at O0 and O2.
    @Test
    func javaUtilQueueDequePlatformReturnsThroughSourceAndFreshArtifactAtO0AndO2() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = try diffCaseSource("java_util_queue_deque_platform_returns.kt", file: #filePath)
        let expected = """
        4
        false
        ax
        ay
        bz
        ap
        bq
        nullr
        empty-poll:true:null:null
        nullable-bind:null
        safe-chain:null
        npe:pollFirst
        npe:unbox
        deque:1:11:23
        deque-poll:2:3:4:0
        deque-empty:true:null
        pq:10:10
        pq-empty:true:true
        queue-iface:6:true
        clq:5:true
        navset:11:20:21:20
        navset-miss:true:true
        navset-poll:11:31
        navmap:2:2:1:false
        navmap-entry:1:one:two
        navmap-poll:1:two:0
        navmap-empty:true:true
        chm:a:true:true
        chm-replace:z!:true
        cm:y:true:false
        chm-compute:v4:v4
        props:v!:true
        take:1

        """
        for optLevel in [OptimizationLevel.O0, .O2] {
            for stdlibLibraryPath in [nil, artifactPath] {
                let output = try Self.runQueueDequeSources(
                    [source], optLevel: optLevel, stdlibLibraryPath: stdlibLibraryPath
                )
                #expect(output == expected,
                        "queue/deque platform returns at \(optLevel), artifact: \(stdlibLibraryPath != nil)")
            }
        }
    }

    private static func runQueueDequeSources(
        _ sources: [String],
        optLevel: OptimizationLevel,
        stdlibLibraryPath: String?
    ) throws -> String {
        var normalizedOutput: String?
        try withTemporaryFiles(contents: sources) { inputs in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "KUU3869QueueDeque",
                inputs: inputs,
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibLibraryPath == nil,
                stdlibLibraryPath: stdlibLibraryPath,
                allowDefaultStdlibLibrary: false
            )
            let context = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
            try LinkPhase().run(context)

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            guard result.exitCode == 0 else {
                throw TestCompilationFailure(
                    description: "KUU-3869 executable failed at \(optLevel): \(result.stderr)"
                )
            }
            #expect(result.stderr.isEmpty, "queue/deque executable stderr: \(result.stderr)")
            normalizedOutput = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
        }
        guard let normalizedOutput else {
            throw TestCompilationFailure(description: "KUU-3869 fixture did not run")
        }
        return normalizedOutput
    }
}
