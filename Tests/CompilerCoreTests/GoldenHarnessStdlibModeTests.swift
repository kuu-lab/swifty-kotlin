@testable import CompilerCore
@testable import CompilerTestSupport
@testable import GoldenHarnessSupport
import Testing
import TestStdlibCache

@Suite
struct GoldenHarnessStdlibModeTests {
    @Test
    func profilesControlStdlibSelection() throws {
        let path = "/tmp/stdlib.kklib"
        let implicit = try GoldenHarnessDump.resolveStdlibMode(spec: nil, stdlibLibraryPath: path)
        #expect(implicit.libraryPath == path)
        let fallback = try GoldenHarnessDump.resolveStdlibMode(spec: nil, stdlibLibraryPath: nil)
        #expect(fallback.includeStdlib)
        #expect(fallback.libraryPath == nil)

        let source = try GoldenHarnessDump.resolveStdlibMode(
            spec: GoldenHarnessCaseSpec(stdlibProfile: .source, targets: []), stdlibLibraryPath: path
        )
        #expect(source.includeStdlib)
        #expect(source.libraryPath == nil)
        let artifact = try GoldenHarnessDump.resolveStdlibMode(
            spec: GoldenHarnessCaseSpec(stdlibProfile: .artifact, targets: []), stdlibLibraryPath: path
        )
        #expect(!artifact.includeStdlib)
        #expect(artifact.libraryPath == path)
        let none = try GoldenHarnessDump.resolveStdlibMode(
            spec: GoldenHarnessCaseSpec(stdlibProfile: .noStdlib, targets: []), stdlibLibraryPath: path
        )
        #expect(!none.includeStdlib)
        #expect(none.libraryPath == nil)
        #expect(throws: GoldenHarnessDumpError.self) {
            try GoldenHarnessDump.resolveStdlibMode(
                spec: GoldenHarnessCaseSpec(stdlibProfile: .artifact, targets: []), stdlibLibraryPath: nil
            )
        }
    }

    @Test
    func sourceProfileDoesNotInheritProcessArtifact() throws {
        TestStdlibCache.shared.prepare()
        let artifactPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = GoldenHarnessSupport.makeCompilationContext(inputs: [path])
            #expect(ctx.options.stdlibLibraryPath == nil)
            #expect(ctx.options.includeStdlib)
            #expect(!ctx.options.allowDefaultStdlibLibrary)
            try LoadSourcesPhase().run(ctx)
            #expect(ctx.sourceManager.fileIDs().contains {
                ctx.sourceManager.origin(of: $0)?.isBundledStdlib == true
            })
            let imported = GoldenHarnessSupport.makeCompilationContext(inputs: [path], stdlibLibraryPath: artifactPath)
            #expect(imported.options.stdlibLibraryPath == artifactPath)
            #expect(!imported.options.includeStdlib)
        }
    }
}
