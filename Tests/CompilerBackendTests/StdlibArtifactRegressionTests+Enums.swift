@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    /// KUU-1320: reified enumValues specializes in both stdlib modes.
    @Test(arguments: [false, true])
    func testReifiedEnumValues(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/enum_values_reified.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ReifiedEnumValues", emit: .executable, outputPath: outputBase,
                stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "[A, B]\n[X, Y, Z]\n[A, B]\n[]\n[SOURCE, BINARY, RUNTIME]\n[A, B]\n[A, B]\n")
        }
    }

    /// KUU-1462: a reified enum token remains available inside a noinline lambda.
    @Test(arguments: [false, true])
    func testReifiedEnumValuesInsideNoinlineLambda(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try testStdlibArtifactPath() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/enum_values_reified_noinline_lambda.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [path], moduleName: "ReifiedEnumValuesNoinlineLambda", emit: .executable,
                outputPath: outputBase, stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "[A, B]\nB\n")
        }
    }

    @Test
    func testReifiedEnumValuesThroughInlineLibrary() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdlib = try testStdlibArtifactPath()
        let librarySource = directory.appendingPathComponent("Factory.kt").path
        let libraryOutput = directory.appendingPathComponent("Factory").path
        try """
        package factory
        inline fun <reified T : Enum<T>> values(unused: Int = 0): List<T> = enumValues<T>().toList()
        inline fun <reified T : Enum<T>> nestedValues(): List<T> = values<T>()
        """.write(toFile: librarySource, atomically: true, encoding: .utf8)
        let library = makeCompilationContext(
            inputs: [librarySource], moduleName: "EnumFactory", emit: .library,
            outputPath: libraryOutput, stdlibLibraryPath: stdlib
        )
        try runToLowering(library)
        try assertNoDiagnosticErrors(library)
        try CodegenPhase().run(library)
        let source = """
        import factory.values
        import factory.nestedValues
        enum class E { A, B }
        fun main() {
            println(values<E>())
            println(nestedValues<E>())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let output = directory.appendingPathComponent("consumer").path
            let consumer = makeCompilationContext(
                inputs: [path], moduleName: "EnumFactoryConsumer", emit: .executable, outputPath: output,
                searchPaths: [libraryOutput + ".kklib"], stdlibLibraryPath: stdlib
            )
            try runToLowering(consumer)
            try assertNoDiagnosticErrors(consumer)
            try CodegenPhase().run(consumer)
            try LinkPhase().run(consumer)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout == "[A, B]\n[A, B]\n")
        }
    }

    /// STDLIB-ARTIFACT-006: enum entry references from a precompiled stdlib
    /// artifact must have their global ordinal slots initialized. The shared
    /// artifact contains the `__enum_static_init_*` function; the consumer's
    /// top-level initializer must call it before `main` so that enum entry
    /// objects such as `Base64.PaddingOption.ABSENT` behave correctly.
    @Test
    func testEnumEntryStaticInitializerSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.io.encoding.Base64
        import kotlin.io.encoding.ExperimentalEncodingApi

        @OptIn(ExperimentalEncodingApi::class)
        fun main() {
            val noPad = Base64.Default.withPadding(Base64.PaddingOption.ABSENT)
            println(noPad.encode("foob".encodeToByteArray()))
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
            #expect(normalizedStdout == "Zm9vYg\n")
        }
    }

    /// STDLIB-ARTIFACT-015: imported synthetic enum entries (e.g.
    /// `RegexOption`) must carry `.constValue` and an ordinal expression so
    /// the shared stdlib path emits `intLiteral` values instead of unresolved
    /// `symbolRef` constants. Otherwise `Regex(..., RegexOption.XXX)` is passed
    /// an object pointer or ignored by the runtime.
    @Test
    func testRegexOptionConstantsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.text.RegexOption

        fun main() {
            println(Regex("[a-z]+", RegexOption.IGNORE_CASE).matches("ABC"))
            println(Regex("^line", RegexOption.MULTILINE).containsMatchIn("first\\nline two"))
            println(Regex("a.b", RegexOption.DOT_MATCHES_ALL).containsMatchIn("a\\nb"))
            println(Regex("[a-z]+", RegexOption.LITERAL).containsMatchIn("[a-z]+"))
            println(Regex(".", RegexOption.UNIX_LINES).containsMatchIn("a"))
            println(Regex("a b  # match ab", RegexOption.COMMENTS).containsMatchIn("ab"))
            println(Regex("[a-z]+", setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)).matches("HELLO"))
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
            #expect(normalizedStdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n")
        }
    }

    /// STDLIB-ARTIFACT-016: source-backed CharDirectionality entries must
    /// preserve ordinal comparisons through the shared stdlib artifact.
    @Test
    func testCharDirectionalityConstantsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        import kotlin.text.CharDirectionality

        fun main() {
            println('A'.directionality == CharDirectionality.LEFT_TO_RIGHT)
            println('\\u05D0'.directionality == CharDirectionality.RIGHT_TO_LEFT)
            println('5'.directionality == CharDirectionality.EUROPEAN_NUMBER)
            println(' '.directionality == CharDirectionality.WHITESPACE)
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
            #expect(normalizedStdout == "true\ntrue\ntrue\ntrue\n")
        }
    }

    /// Imported enum declarations have no AST, so the per-decl synthesis that
    /// normally registers `values()` / `valueOf(_:)` / `entries` / `name` /
    /// `ordinal` never ran for them. Consumers of a precompiled stdlib
    /// artifact must still resolve the full implicit enum API.
    @Test
    func testImportedEnumImplicitMembersThroughPrecompiledStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        @file:OptIn(kotlin.native.concurrent.ObsoleteWorkersApi::class)

        import kotlin.native.concurrent.FutureState
        import kotlin.native.concurrent.TransferMode

        fun main() {
            println(FutureState.entries.size)
            println(FutureState.INVALID.value)
            println(FutureState.SCHEDULED.value)
            println(FutureState.COMPUTED.value)
            println(FutureState.CANCELLED.value)
            println(FutureState.THROWN.value)
            println(FutureState.valueOf(name = "THROWN").value)
            println(FutureState.values().size)

            println(TransferMode.entries.size)
            println(TransferMode.SAFE.value)
            println(TransferMode.valueOf("UNSAFE").value)
            println(TransferMode.values().size)
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "ImportedEnumMembersArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Imported enum implicit members should resolve: \(ctx.diagnostics.diagnostics)"
            )

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
                5
                0
                1
                2
                3
                4
                4
                5
                2
                0
                1
                2

                """)
        }
    }
}
