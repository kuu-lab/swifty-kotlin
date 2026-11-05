@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct MapEntrySourceContractTests {
    @Test(arguments: [false, true])
    func entryAndGettersAreOwnedByBundledSource(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: ["fun key(entry: Map.Entry<String, Int>): String = entry.key"]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "collections", "Map", "Entry"].map(ctx.interner.intern)
            let entry = try #require(sema.symbols.lookup(fqName: fq))
            #expect(sema.types.nominalTypeParameterSymbols(for: entry).count == 2)
            #expect(sema.types.nominalTypeParameterVariances(for: entry) == [.out, .out])
            for path in [fq, fq + [ctx.interner.intern("key")], fq + [ctx.interner.intern("value")]] {
                let symbol = try #require(sema.symbols.lookup(fqName: path))
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.importedLibrary) == useArtifact)
                if !useArtifact {
                    #expect(sema.symbols.isSourceBackedSymbol(symbol))
                    #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false)
                    #expect(sema.symbols.externalLinkName(for: symbol) == nil)
                }
            }
        }
    }

    /// KUU-4304: a root-package `Map.Entry` must not shadow the
    /// default-imported `kotlin.collections.Map.Entry` inside named
    /// packages — the same ordering bug as the `Number` supertype case, but
    /// through the qualified-name path used by both supertype and signature
    /// type resolution.
    @Test(arguments: [false, true])
    func rootPackageMapEntryDoesNotShadowKotlinCollectionsEntry(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try withTemporaryFiles(contents: [
            """
            class Map {
                open class Entry
            }
            """,
            """
            package shadowed
            abstract class Impl : Map.Entry<String, Int>
            fun takes(entry: Map.Entry<String, Int>): Map.Entry<String, Int> = entry
            """,
        ]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths,
                emit: useArtifact ? .executable : .kirDump,
                allowDefaultStdlibLibrary: useArtifact
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let kotlinEntry = try #require(sema.symbols.lookup(fqName: [
                "kotlin", "collections", "Map", "Entry",
            ].map(interner.intern)))
            let rootEntry = try #require(sema.symbols.lookup(fqName: [
                "Map", "Entry",
            ].map(interner.intern)))
            let impl = try #require(sema.symbols.lookup(fqName: [
                "shadowed", "Impl",
            ].map(interner.intern)))
            #expect(sema.symbols.directSupertypes(for: impl).contains(kotlinEntry))
            #expect(!sema.symbols.directSupertypes(for: impl).contains(rootEntry))
        }
    }

    @Test
    func nestedInterfaceBoundResolvesImportAlias() throws {
        let sources = [
            "package bounds; interface Base",
            """
            import bounds.Base as Limit
            interface Host { interface Child<T : Limit> { val value: T } }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let child = try #require(sema.symbols.lookup(fqName: ["Host", "Child"].map(ctx.interner.intern)))
            let parameter = try #require(sema.types.nominalTypeParameterSymbols(for: child).first)
            let bounds = sema.symbols.typeParameterUpperBounds(for: parameter)
            #expect(bounds.count == 1)
            let bound = try #require(bounds.first)
            guard case let .classType(type) = sema.types.kind(of: bound) else {
                Issue.record("Expected a resolved nominal bound")
                return
            }
            #expect(sema.symbols.symbol(type.classSymbol)?.fqName == ["bounds", "Base"].map(ctx.interner.intern))
        }
    }
}
