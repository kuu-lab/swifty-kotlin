@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import RuntimeABI
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
    func publishedAPIInternalInlineHelperRemainsCallableThroughLibrary() throws {
        try withCompiledLibrary(
            source: """
            package publishedcleanup
            @PublishedApi internal inline fun hidden(): Int {
                try { return 55 } finally { println("hidden-finally") }
            }
            inline fun exposed(): Int = hidden()
            """,
            moduleName: "PublishedInlineCleanup"
        ) { libraryPath in
            try withTemporaryFile(contents: """
            import publishedcleanup.exposed
            fun caller(): Int {
                try { return exposed() } finally { println("caller-finally") }
            }
            fun main() { println(caller()) }
            """) { path in
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
                #expect(result.stdout == "hidden-finally\ncaller-finally\n55\n")
            }
        }
    }

    @Test
    func importedInlineFunctionKeepsOwnNonLocalReturnTarget() throws {
        try withCompiledLibrary(
            source: """
            package returntarget
            @PublishedApi internal inline fun hidden(): Int {
                try { around { return 55 } } finally { println("hidden-finally") }
                return -1
            }
            inline fun exposed(): Int = hidden()
            inline fun around(block: () -> Unit) { block() }
            inline fun value(): Int {
                try { around { return 42 } } finally { println("value-finally") }
                return -1
            }
            inline fun nested(): Int {
                try { return value() + 1 } finally { println("nested-finally") }
            }
            inline fun capturing(): Int {
                var answer = 53
                around { answer += 1; return answer }
                return -1
            }
            """,
            moduleName: "InlineReturnTarget"
        ) { libraryPath in
            let inlineDirectory = URL(fileURLWithPath: libraryPath).appendingPathComponent("inline-kir")
            let artifacts = try FileManager.default.contentsOfDirectory(at: inlineDirectory, includingPropertiesForKeys: nil)
            let serialized = try artifacts.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
            #expect(serialized.contains("targetB64="))
            #expect(serialized.contains("functionB64="))
            // Lambdas carrying non-local returns are `isInlineOnly` and never
            // reach an object file, so serializing their link name would leave
            // a dangling extern reference in consumers (KUU-1207). Emitted
            // functions legitimately keep extern refs, so check definedness
            // rather than the symbol's name shape.
            let externLinkNames = serialized
                .split(whereSeparator: \.isWhitespace)
                .compactMap { token -> String? in
                    guard let range = token.range(of: "externB64:"),
                          let data = Data(base64Encoded: String(token[range.upperBound...])),
                          let name = String(data: data, encoding: .utf8)
                    else { return nil }
                    return name
                }
            let moduleExternNames = Set(externLinkNames.filter { $0.hasPrefix(RuntimeABISpec.compilerGeneratedLinkNamePrefix) })
            let definedObjectSymbols = try Self.definedObjectSymbols(in: libraryPath)
            #expect(moduleExternNames.isSubset(of: definedObjectSymbols))
            let source = """
            import returntarget.value
            import returntarget.nested
            import returntarget.exposed
            import returntarget.capturing
            fun main() {
                println("before")
                try {
                    println(value())
                    println(value())
                    println(nested())
                    println("after-value")
                } finally { println("main-finally") }
                println("after")
                println(exposed())
                println("after-hidden")
                println(capturing())
                println("after-capture")
            }
            """
            try withTemporaryFile(contents: source) { path in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let context = makeCompilationContext(
                    inputs: [path], emit: .executable, outputPath: output, searchPaths: [libraryPath]
                )
                try runToKIR(context)
                try LoweringPhase().run(context)
                #expect(!context.diagnostics.hasError)
                try CodegenPhase().run(context)
                try LinkPhase().run(context)
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "before\nvalue-finally\n42\nvalue-finally\n42\nvalue-finally\nnested-finally\n43\nafter-value\nmain-finally\nafter\nhidden-finally\n55\nafter-hidden\n54\nafter-capture\n")
            }
        }
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

    /// Names of symbols defined in the library's emitted object files, taken
    /// from `nm` output (`<addr> <type> <name>` lines; undefined references
    /// print without an address). Darwin's leading-underscore decoration is
    /// stripped.
    private static func definedObjectSymbols(in libraryPath: String) throws -> Set<String> {
        let objectsURL = URL(fileURLWithPath: libraryPath).appendingPathComponent("objects")
        let objectFiles = try FileManager.default.contentsOfDirectory(atPath: objectsURL.path)
            .filter { $0.hasSuffix(".o") }
        var defined = Set<String>()
        for objectFile in objectFiles {
            let result = try CommandRunner.run(
                executable: CommandRunner.resolveExecutable("nm", fallback: "/usr/bin/nm"),
                arguments: [objectsURL.appendingPathComponent(objectFile).path]
            )
            for line in result.stdout.split(separator: "\n") {
                let fields = line.split(separator: " ")
                guard fields.count >= 3, fields[1].count == 1, fields[1] != "U" else { continue }
                var name = fields[2]
                if name.hasPrefix("_") { name = name.dropFirst() }
                defined.insert(String(name))
            }
        }
        return defined
    }
}
