import Foundation
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct LambdaBlockAnonymousFunctionExecutionTests {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func assertMatchesKotlin(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = repository.appendingPathComponent(
            "Scripts/diff_cases/kuu_2344_lambda_block_anonymous_function.kt"
        )
        let input = directory.appendingPathComponent("anonymous_function.kt").path
        let output = directory.appendingPathComponent("anonymous_function").path
        try FileManager.default.copyItem(at: fixture, to: URL(fileURLWithPath: input))

        let level = try #require(OptimizationLevel(rawValue: optimization))
        let artifact = fromSource ? nil : try testStdlibArtifactPath()
        let options = CompilerOptions(
            moduleName: "LambdaBlockAnonymousFunction",
            inputs: [input],
            outputPath: output,
            emit: .executable,
            target: CompilerTestSupport.defaultTargetTriple(),
            optLevel: level,
            includeStdlib: fromSource,
            stdlibLibraryPath: artifact,
            allowDefaultStdlibLibrary: !fromSource
        )

        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
        let result = try CommandRunner.run(executable: output, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        #expect(result.stdout == "OK\n")
    }

    @Test
    func bundledSourceAtO0MatchesKotlin() throws {
        // KUU-2241 tracks a separate high-arity function-invoke LLVM verifier
        // failure in bundled-source O2 builds; keep this source-mode check at O0.
        try assertMatchesKotlin(fromSource: true, optimization: 0)
    }

    @Test(arguments: [0, 2])
    func freshStdlibArtifactMatchesKotlin(optimization: Int) throws {
        try assertMatchesKotlin(fromSource: false, optimization: optimization)
    }
}
