@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

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

    @Test
    func testTrimIndentAndMarginConstantResultsAreInterned() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = #"""
        fun constantIndent() = """
            Hello,
            World
        """.trimIndent()

        fun constantMargin() = """
            |Hello,
            |World
        """.trimMargin()

        fun customMargin() = """
            >Hello,
            >World
        """.trimMargin(">")

        fun main() {
            println(constantIndent() === constantIndent())
            println(constantMargin() === constantMargin())
            println(customMargin() === customMargin())
        }
        """#

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = CompilerTestSupport.makeCompilationContext(
                inputs: [userPath],
                moduleName: "StringIndentConstants",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "true\ntrue\ntrue\n")
        }
    }

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
