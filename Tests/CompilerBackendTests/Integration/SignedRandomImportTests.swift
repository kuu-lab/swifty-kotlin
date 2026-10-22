#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// KUU-2775: signed range overloads are imported extensions, not Random members.
@Suite
struct SignedRandomImportTests {
    @Test(arguments: [false, true])
    func acceptsExplicitAliasAndWildcardImports(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        for imports in [
            "import kotlin.random.Random\nimport kotlin.random.nextInt\nimport kotlin.random.nextLong",
            "import kotlin.random.*",
            "import kotlin.random.Random\nimport kotlin.random.nextInt as intInRange\nimport kotlin.random.nextLong as longInRange",
        ] {
            let intName = imports.contains("as intInRange") ? "intInRange" : "nextInt"
            let longName = imports.contains("as longInRange") ? "longInRange" : "nextLong"
            let source = """
            \(imports)
            fun ranges(random: Random) {
                random.nextInt()
                random.nextInt(10)
                random.nextInt(1, 10)
                val a: Int = random.\(intName)(1..10)
                val b: Int = random.\(intName)(range = 1..10)
                val c: Int = Random.\(intName)(1..10)
                val d: Int = Random.Default.\(intName)(1..10)

                random.nextLong()
                random.nextLong(10L)
                random.nextLong(1L, 10L)
                val e: Long = random.\(longName)(1L..10L)
                val f: Long = random.\(longName)(range = 1L..10L)
                val g: Long = Random.\(longName)(1L..10L)
                val h: Long = Random.Default.\(longName)(1L..10L)
            }
            fun optional(random: Random?) {
                val a: Int? = random?.\(intName)(1..10)
                val b: Long? = random?.\(longName)(1L..10L)
            }
            fun main() {}
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(
                    inputs: [path], includeStdlib: !artifact,
                    stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
                )
                try runSema(ctx)
                #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            }
        }
    }

    @Test(arguments: [false, true])
    func rejectsRangeCallsWithoutExtensionImports(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        let sources = [
            """
            import kotlin.random.Random
            fun missingInt(random: Random) {
                random.nextInt(1..20)
                Random.nextInt(1..20)
            }
            """,
            """
            import kotlin.random.Random
            fun missingLong(random: Random) {
                random.nextLong(1L..20L)
                Random.nextLong(1L..20L)
            }
            """,
            """
            import kotlin.random.Random
            import kotlin.random.nextInt as intInRange
            import kotlin.random.nextLong as longInRange
            fun aliasDoesNotExposeOriginalNames(random: Random) {
                random.nextInt(1..20)
                random.nextLong(1L..20L)
            }
            """,
        ]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = try sources.enumerated().map { index, source -> String in
            let path = directory.appendingPathComponent("signed_random_scope_\(index).kt").path
            try source.write(toFile: path, atomically: true, encoding: .utf8)
            return path
        }

        let ctx = makeCompilationContext(
            inputs: paths, includeStdlib: !artifact,
            stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
        )
        do { try runSema(ctx) } catch { }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        for path in paths {
            #expect(errors.contains { diagnostic in
                guard let file = diagnostic.primaryRange?.start.file else { return false }
                return ctx.sourceManager.path(of: file) == path
            }, "Expected rejection in \(path): \(errors)")
        }
        #expect(!errors.contains { $0.message.contains("Unresolved import") })
    }

    @Test(arguments: [false, true])
    func signedMembersRemainVisibleAndExtensionImportsStayFileScoped(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        try withTemporaryFile(contents: """
        import kotlin.random.Random
        import kotlin.random.nextInt
        import kotlin.random.nextLong
        fun imported(random: Random) {
            random.nextInt(1..10)
            random.nextLong(1L..10L)
            Random.nextInt(1..10)
            Random.nextLong(1L..10L)
        }
        """) { importedPath in
            try withTemporaryFile(contents: """
            import kotlin.random.Random
            fun membersRemainVisible(random: Random) {
                random.nextInt()
                random.nextInt(10)
                random.nextInt(1, 10)
                Random.nextInt(1, 10)
                random.nextLong()
                random.nextLong(10L)
                random.nextLong(1L, 10L)
                Random.nextLong(1L, 10L)
            }
            fun missingExtensions(random: Random) {
                random.nextInt(1..10)
                random.nextLong(1L..10L)
            }
            """) { missingPath in
                let ctx = makeCompilationContext(
                    inputs: [importedPath, missingPath], includeStdlib: !artifact,
                    stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
                )
                do { try runSema(ctx) } catch { }
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(!errors.isEmpty, "The missing range imports should be rejected")
                #expect(errors.allSatisfy { diagnostic in
                    guard let file = diagnostic.primaryRange?.start.file else { return false }
                    return ctx.sourceManager.path(of: file) == missingPath
                }, "\(errors)")
            }
        }
    }
}
#endif
