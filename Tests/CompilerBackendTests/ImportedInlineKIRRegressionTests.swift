@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Regression coverage for imported inline KIR callback result types.
@Suite
struct ImportedInlineKIRRegressionTests {
    private static let artifactLock = NSLock()
    nonisolated(unsafe) private static var cachedArtifactPath: String?

    private static func buildStdlibArtifact() throws -> String {
        artifactLock.lock()
        defer { artifactLock.unlock() }

        if let cachedArtifactPath {
            return cachedArtifactPath
        }

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSP1374-ImportedInlineKIR-\(UUID().uuidString)")
            .path
        let ctx = makeCompilationContext(
            inputs: [],
            moduleName: "KSwiftKStdlib",
            emit: .library,
            outputPath: outputBase,
            includeStdlib: true,
            stdlibOnly: true
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)

        let artifactPath = outputBase + ".kklib"
        #expect(FileManager.default.fileExists(atPath: artifactPath))
        #expect(FileManager.default.fileExists(atPath: artifactPath + "/inline-kir"))
        cachedArtifactPath = artifactPath
        return artifactPath
    }

    @Test
    func importedInlineFinallyRunsBeforeCallerFinally() throws {
        try withCompiledLibrary(
            source: """
            package cleanup
            inline fun guarded(block: () -> Unit) {
                try { block() } finally { println("imported-finally") }
            }
            """,
            moduleName: "InlineCleanup"
        ) { libraryPath in
            let inlineDirectory = URL(fileURLWithPath: libraryPath).appendingPathComponent("inline-kir")
            let artifacts = try FileManager.default.contentsOfDirectory(at: inlineDirectory, includingPropertiesForKeys: nil)
            let serialized = try artifacts.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
            #expect(serialized.contains("beginNonLocalReturnScope"))
            #expect(serialized.contains("resumeNonLocalReturn"))
            let source = """
            import cleanup.guarded
            fun escape(): Int {
                try { guarded { return 31 } } finally { println("caller-finally") }
                return -1
            }
            fun main() { println(escape()) }
            """
            try withTemporaryFile(contents: source) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output, searchPaths: [libraryPath]
                )
                try runToLowering(context)
                #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "imported-finally\ncaller-finally\n31\n")
            }
        }
    }

    @Test
    func importedFirstPredicateFalseBranchRunsThroughArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        private fun firstNonLocal(source: CharSequence): Char {
            source.first {
                if (it == 'x') return '!'
                false
            }
            return '?'
        }

        fun main() {
            println(firstNonLocal("ax").code)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSP1374-ImportedInlineKIR-User-\(UUID().uuidString)")
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1374ImportedInlineKIRUser",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "33\n")
        }
    }

    @Test
    func importedFlatMapWithoutThrowDoesNotRethrowZeroFallback() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            println(listOf('a', 'b').flatMap { listOf(it) })
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSP1374-ImportedInlineKIR-FlatMap-\(UUID().uuidString)")
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1374ImportedInlineKIRFlatMap",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "[a, b]\n")
        }
    }

    @Test
    func importedFlatMapPropagatesAndCatchesCallbackException() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        fun main() {
            val marker = try {
                listOf('a').flatMap { throw IllegalStateException("callback") }
                "not-caught"
            } catch (e: IllegalStateException) {
                "caught"
            }
            println(marker)
        }
        """

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("KSP1374-ImportedInlineKIR-FlatMapThrow-\(UUID().uuidString)")
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "KSP1374ImportedInlineKIRFlatMapThrow",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "caught\n")
        }
    }
}
