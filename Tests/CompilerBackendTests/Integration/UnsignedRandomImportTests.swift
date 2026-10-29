@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// KUU-2061: unsigned random overloads are imported extensions, not members.
@Suite
struct UnsignedRandomImportTests {
    @Test(arguments: [false, true])
    func acceptsExplicitAliasAndWildcardImports(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        for imports in [
            "import kotlin.random.Random\nimport kotlin.random.nextUInt\nimport kotlin.random.nextULong",
            "import kotlin.random.*",
            "import kotlin.random.Random\nimport kotlin.random.nextUInt as uintBits\nimport kotlin.random.nextULong as ulongBits",
        ] {
            let uintName = imports.contains("as uintBits") ? "uintBits" : "nextUInt"
            let ulongName = imports.contains("as ulongBits") ? "ulongBits" : "nextULong"
            let source = """
            \(imports)
            fun bits(random: Random) {
                val a: UInt = random.\(uintName)()
                val b: UInt = random.\(uintName)(until = 10u)
                val c: UInt = random.\(uintName)(from = 1u, until = 10u)
                val d: UInt = random.\(uintName)(range = 1u..10u)
                val e: ULong = random.\(ulongName)()
                val f: ULong = random.\(ulongName)(until = 10uL)
                val g: ULong = random.\(ulongName)(from = 1uL, until = 10uL)
                val h: ULong = random.\(ulongName)(range = 1uL..10uL)
                val i: UInt = Random.\(uintName)()
                val j: ULong = Random.\(ulongName)()
                val k: ULong = Random.Default.\(ulongName)()
            }
            fun optional(random: Random?) {
                val a: UInt? = random?.\(uintName)()
                val b: ULong? = random?.\(ulongName)()
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
                let sema = try #require(ctx.sema)
                for name in ["nextUInt", "nextULong"] {
                    let packagePath = ["kotlin", "random", name].map(ctx.interner.intern)
                    #expect(sema.symbols.lookupAll(fqName: packagePath).count == 4)
                    for owner in [["kotlin", "random", "Random"], ["kotlin", "random", "Random", "Default"]] {
                        #expect(sema.symbols.lookupAll(fqName: (owner + [name]).map(ctx.interner.intern)).isEmpty)
                    }
                }
            }
        }
    }

    @Test(arguments: [false, true])
    func preservesRejectionBoundaries(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var paths: [String] = []
        for name in ["nextUInt", "nextULong"] {
            let cases = [
                "import kotlin.random.Random\nfun probe(random: Random) = random.\(name)()",
                "import kotlin.random.Random\nimport kotlin.random.\(name) as bits\nfun probe(random: Random) = random.\(name)()",
                "import kotlin.random.*\nfun probe(random: Random?) = random.\(name)()",
                "import kotlin.random.*\nfun probe(random: Random) = random.\(name)<Int>()",
                "import kotlin.random.*\nfun probe(random: Random) = random.\(name)(1..10)",
            ]
            for (index, source) in cases.enumerated() {
                let path = directory.appendingPathComponent("\(name)_\(index).kt").path
                let uniqueSource = source.replacingOccurrences(of: "fun probe(", with: "fun probe_\(name)_\(index)(")
                try uniqueSource.write(toFile: path, atomically: true, encoding: .utf8)
                paths.append(path)
            }
        }
        // Each file keeps independent imports while sharing one stdlib source compilation.
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
    func importDoesNotLeakBetweenFilesAndSignedMembersRemainVisible(artifact: Bool) throws {
        let library = artifact ? try testStdlibArtifactPath() : nil
        try withTemporaryFile(contents: """
        import kotlin.random.Random
        import kotlin.random.nextULong
        fun imported(random: Random): ULong = random.nextULong()
        """) { importedPath in
            try withTemporaryFile(contents: """
            import kotlin.random.Random
            fun signed(random: Random) { val a: Int = random.nextInt(); val b: Long = random.nextLong() }
            fun missing(random: Random): ULong = random.nextULong()
            """) { otherPath in
                let ctx = makeCompilationContext(
                    inputs: [importedPath, otherPath], includeStdlib: !artifact,
                    stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
                )
                do { try runSema(ctx) } catch { }
                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.count == 1, "\(errors)")
                #expect(errors.first?.message.contains("nextULong") == true)
            }
        }
    }
}
