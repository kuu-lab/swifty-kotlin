@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing
import TestStdlibCache

extension StdlibArtifactRegressionTests {

    @Test(arguments: [false, true])
    func testStringLengthPropertyReferencesPreserveGetterABI(useArtifact: Bool) throws {
        let artifactPath = useArtifact ? try Self.buildStdlibArtifact() : nil
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/callable_ref_string_length.kt"
        ), encoding: .utf8)
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "StringLengthPropertyReferences",
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
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            [1, 2]
            3
            [0, 6]
            4
            5
            [0, 2, 2]
            6
            6
            6
            6
            [[x], [yy]]
            [z]

            """)
        }
    }

    /// STDLIB-ARTIFACT-009: synthetic operator extension functions (e.g.
    /// `CharSequence.get`) must not shadow source-backed member functions
    /// (e.g. `StringBuilder.get`) in the default-import scope. Inside
    /// `buildString { append(get(1)) }`, `get(1)` must resolve to the real
    /// `StringBuilder.get` member and print the correct character.
    @Test
    func testBuildStringReceiverGetSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println(buildString { append("abc"); append(get(1)) })
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
            #expect(normalizedStdout == "abcb\n")
        }
    }

    /// STDLIB-ARTIFACT-011: synthetic `String.contains` extension must bind a real
    /// call symbol through the shared stdlib artifact so KIR lowering emits the
    /// dedicated `kk_string_contains_str_flat` helper instead of a generic
    /// `kk_op_contains` dispatch. This regresses when pure synthetic operator
    /// extensions are excluded from the default-import scope and the string
    /// fallback returns a type without a `CallBinding`.
    @Test
    func testStringContainsSharedPath() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            println("Kotlin".contains("otl"))
            println("Kotlin".contains("abc"))
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
            #expect(normalizedStdout == "true\nfalse\n")
        }
    }

    /// STDLIB-ARTIFACT-CHARSEQUENCE-SUBSEQUENCE: `subSequence` reached through a
    /// value statically typed as `CharSequence` (backed by `String`) must resolve
    /// to bundled Kotlin source (`Stdlib/kotlin/text/StringSubstringSlice.kt`) when
    /// compiling against a prebuilt stdlib artifact, not the removed
    /// `kk_string_subSequence_flat` runtime ABI (KSP-406). This is the shared-path
    /// analogue of `Scripts/diff_cases/char_sequence_member_access.kt`: the flake it
    /// guards only surfaced through `--no-stdlib --stdlib-library` linking, where an
    /// undefined reference to `kk_string_subSequence_flat` failed the link.
    @Test
    func testCharSequenceSubSequenceThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = try diffCaseSource("char_sequence_member_access.kt", file: #filePath)

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
            #expect(normalizedStdout == "5\n6\no\nr\nor\n3\nb\nc\n")
        }
    }

    /// STDLIB-ARTIFACT-STRING-INDENT: the indent-formatting family
    /// (`trimIndent`/`trimMargin`/`prependIndent`/`replaceIndent`/
    /// `replaceIndentByMargin`) must resolve to bundled Kotlin source
    /// (`Stdlib/kotlin/text/StringIndentFormat.kt`) when compiling against a
    /// prebuilt stdlib artifact, not the removed `kk_string_*_flat` runtime ABI.
    /// This is the shared-path analogue of the `raw_string_basic`,
    /// `string_indent`, `trim_margin` and `string_replaceindentbymargin` diff
    /// cases, whose failure mode was an undefined reference to
    /// `kk_string_trimIndent_flat` (and friends) at link time under
    /// `--no-stdlib --stdlib-library`.
    @Test
    func testStringIndentFormattingThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = #"""
        fun marker(value: String) {
            println(value.replace("\n", "/"))
        }

        fun main() {
            val raw = """
                line1
                line2
            """.trimIndent()
            marker(raw)
            marker("\n    |alpha\n    |beta\n".trimMargin())
            marker("\n    >alpha\n    >beta\n".trimMargin(">"))
            marker("Hello\nWorld".prependIndent())
            marker("Hello\nWorld".prependIndent(">>"))
            marker("  Hello\n  World".replaceIndent())
            marker("  Hello\n  World".replaceIndent("--"))
            marker("\n    |alpha\n    |beta\n".replaceIndentByMargin())
            marker("\n    |alpha\n    |beta\n".replaceIndentByMargin("> ", "|"))
        }
        """#

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
            #expect(normalizedStdout == """
                line1/line2
                alpha/beta
                alpha/beta
                    Hello/    World
                >>Hello/>>World
                Hello/World
                --Hello/--World
                alpha/beta
                > alpha/> beta

                """)
        }
    }

    /// STDLIB-ARTIFACT-INLINE-ONLY-LAMBDA: `joinToString(separator) { ... }` is
    /// an auto-inline overload of the bundled `kotlin.collections` source, so no
    /// standalone body reaches the stdlib artifact. When such a call sits inside
    /// a lambda that is itself spliced into its caller (here the `let` body),
    /// the spliced instructions must be re-scanned for inline expansion;
    /// otherwise the consumer keeps an undefined reference to `kk_fn_joinToString_*`
    /// at link time (the `compiler_plugin_api` diff case failure mode).
    @Test
    func testInlineOnlyCallInsideSplicedLambdaThroughSharedStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()

        let source = """
        fun main() {
            val options: Map<String, String> = mapOf("k" to "v", "a" to "b")
            val summary = options.entries.let { entries ->
                entries.sortedBy { it.key }.joinToString(",") { "${it.key}=${it.value}" }
            }
            println(summary)
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
            #expect(normalizedStdout == "a=b,k=v\n")
        }
    }
}
