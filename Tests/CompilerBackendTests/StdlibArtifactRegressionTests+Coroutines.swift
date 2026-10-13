@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-1022: interface bridges must preserve source overrides and captures.
    @Test(arguments: [false, true])
    func testCoroutineContextOverrideDispatch(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/coroutine_context_override_dispatch.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CoroutineContextOverrideDispatch",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "0\ntrue\ntrue\ntrue\ntrue\n13\ntrue\ntrue\ninherited plus\n16\ntrue\ntrue\ntrue\ntrue\nstart:item:item\nfold override\nplus override\nplus override\nplus override\ntrue\n")
        }
    }

    @Test(arguments: [false, true])
    func testContinuationContextOverrides(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/continuation_context_override.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "ContinuationContextOverrides",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\ngetter\ntrue\ntrue\ntrue\n7\n42\n")
        }
    }

    @Test
    func testContinuationInterceptorThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/stdlib_kotlin_coroutines_ContinuationInterceptor_ContinuationInterceptor_n.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ContinuationInterceptorArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            let expected = String(repeating: "true\n", count: 15) + "resumed\ndefault released\n1\n"
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    @Test
    func testNativeDispatcherInterceptorThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlin.coroutines.*
        import kotlinx.coroutines.Dispatchers

        class Done : Continuation<Unit> {
            override val context: CoroutineContext = EmptyCoroutineContext
            override fun resumeWith(result: Result<Unit>) {}
        }
        fun main() {
            val original = Done()
            val direct = Dispatchers.Default.interceptContinuation(original)
            val interceptor: ContinuationInterceptor = Dispatchers.Default
            val indirect = interceptor.interceptContinuation(original)
            println(direct === indirect)
            interceptor.releaseInterceptedContinuation(indirect)
            println("released")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "NativeInterceptorArtifact",
                emit: .executable, outputPath: outputBase,
                includeStdlib: false, stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\nreleased\n")
        }
    }

    @Test(arguments: [false, true])
    func testDispatcherNames(useArtifact: Bool) throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = useArtifact ? CompilerOptions.defaultStdlibLibraryPath : nil
        if useArtifact {
            try #require(artifactPath != nil, "shared stdlib artifact must be available")
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/dispatchers_to_string.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath], moduleName: "DispatcherNames",
                emit: .executable, outputPath: outputBase,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "stderr: \(result.stderr)")
            let expected = """
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            Dispatchers.IO
            Dispatchers.Unconfined
            Dispatchers.Default
            [Dispatchers.IO, Dispatchers.Unconfined, Dispatchers.Default]
            false
            false
            true
            1263223809
            1263223810
            1263223812
            [1263223809, 1263223810, 1263223812]
            io
            unconfined
            Dispatchers.IO
            true
            Dispatchers.Unconfined
            true
            true

            """
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == expected)
        }
    }

    /// KSP-1151: source-backed coroutine intrinsic fallbacks must not leave a
    /// direct reference to the Kotlin parameter `function` in the stdlib
    /// artifact. A trivial artifact consumer is enough to exercise the native
    /// linker against every object emitted by the stdlib-only build.
    @Test
    func testCoroutineIntrinsicFallbackThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            println("ok")
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "CoroutineIntrinsicArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "ok\n")
        }
    }
}
