@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// STDLIB-ARTIFACT-003: built-in exception constructors are runtime factories
    /// (`kk_*_exception_new_message`) and must not receive an implicit `this`
    /// allocated by `kk_object_new`; otherwise the message handle is misread and
    /// `Throwable.message` is empty in the consumer.
    @Test
    func testExceptionMessageThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            try {
                throw IllegalStateException("shared boom")
            } catch (e: IllegalStateException) {
                println("caught: ${e.message}")
            }
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "caught: shared boom\n")
        }
    }

    /// KUU-1040: primary constructor properties can override the open message
    /// and cause properties through the bundled exception hierarchy in both modes.
    @Test(arguments: [false, true])
    func testThrowableConstructorPropertyOverrides(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/throwable_constructor_property_override.kt"
        ), encoding: .utf8)

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ThrowableConstructorPropertyOverrides",
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
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            invalid input
            true
            invalid input
            root
            invalid input
            true
            missing field
            true
            invalid input
            root

            """)
        }
    }

    /// KUU-594: user-defined Throwable subclasses must initialize the object
    /// allocated by the consumer module when their superclass constructor is
    /// imported from the precompiled stdlib artifact. Runtime factory
    /// constructors need accessor-based initialization, while source-backed
    /// RuntimeException constructors must retain their normal super call.
    @Test
    func testUserDefinedThrowableSubclassThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        class MyEx(msg: String, cause: Throwable? = null) : RuntimeException(msg, cause)
        class MyEx2(msg: String) : Exception(msg)
        class MyEx3 : RuntimeException("fixed")
        open class BaseEx(m: String) : Exception(m)
        class SubEx(m: String) : BaseEx(m)

        fun main() {
            try {
                throw MyEx("boom", IllegalArgumentException("root"))
            } catch (e: MyEx) {
                println("${e.message} / ${e.cause?.message} / ${e.cause is IllegalArgumentException} / $e")
            }
            try {
                throw MyEx2("m2")
            } catch (e: Exception) {
                println("${e.message} / $e")
            }
            try {
                throw MyEx3()
            } catch (e: RuntimeException) {
                println("${e.message} / $e")
            }
            try {
                throw SubEx("sub")
            } catch (e: BaseEx) {
                println("${e.message} / $e / ${e is SubEx}")
            }
            println(RuntimeException("rt").message)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "UserDefinedThrowableArtifact",
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            let expectedStdout = [
                "boom / root / true / MyEx: boom",
                "m2 / MyEx2: m2",
                "fixed / MyEx3: fixed",
                "sub / SubEx: sub / true",
                "rt",
            ].joined(separator: "\n") + "\n"
            #expect(normalizedStdout == expectedStdout)
        }
    }

    /// STDLIB-ARTIFACT-014: member properties with custom getters (e.g.
    /// `Result.isSuccess`/`isFailure`) must round-trip through the shared stdlib
    /// artifact with `propertyGetterExternalLinkName`. Otherwise the consumer
    /// falls back to a field-offset read and crashes or misreads the value.
    @Test
    func testResultMemberPropertyGetterSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val s = runCatching { 10 }
            val f = runCatching { throw RuntimeException("x") }
            println("s.isSuccess=${s.isSuccess} s.isFailure=${s.isFailure}")
            println("f.isSuccess=${f.isSuccess} f.isFailure=${f.isFailure}")
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "s.isSuccess=true s.isFailure=false\nf.isSuccess=false f.isFailure=true\n")
        }
    }

    @Test(arguments: [false, true])
    func testResultInlineSuspension(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/result_inline_suspend.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ResultInlineSuspension", emit: .executable, outputPath: output,
                includeStdlib: !useArtifact, stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "flush\nflush\n7\nsuspended\n7\n14\ntrue\nsuspended\n14\n7\n14\n7\n7\n7\n7\nsuspended\nsuspended\n9\nsuspended\nfinally\n7\n")
        }
    }

    @Test(arguments: [false, true])
    func testResultGetOrDefaultPreservesFallback(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let source = """
        fun main() {
            val failed = runCatching { throw IllegalStateException("x") }
            val success = runCatching { 42 }
            println(failed.getOrDefault(-2))
            println(success.getOrDefault(-2))
            println(failed.getOrDefault("fallback"))
            println(runCatching { null }.getOrDefault(-2))
            println(runCatching<Int> { throw IllegalStateException("typed") }.getOrDefault(-3))
            val absent: Result<Nothing>? = null
            val present: Result<Nothing>? = failed
            println(absent?.getOrDefault(-4))
            println(present?.getOrDefault(-4))
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ResultGetOrDefault",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: !useArtifact,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "-2\n42\nfallback\nnull\n-3\nnull\n-4\n")
        }
    }

    /// STDLIB-ARTIFACT-022: direct construction must use RuntimeResultBox rather
    /// than the ordinary Kotlin object allocation path.
    @Test
    func testResultConstructorUsesRuntimeSuccessFactory() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        fun main() {
            val result: Result<Int> = Result(7)
            println(result.isSuccess)
            println(result.getOrThrow())
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "true\n7\n")
        }
    }
}
