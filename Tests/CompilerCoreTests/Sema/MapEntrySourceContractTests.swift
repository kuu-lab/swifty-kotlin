@testable import CompilerCore
import Testing

@Suite
struct MapEntrySourceContractTests {
    @Test(arguments: [false, true])
    func entryAndGettersAreOwnedByBundledSource(useArtifact: Bool) throws {
        try withTemporaryFiles(contents: ["fun key(entry: Map.Entry<String, Int>): String = entry.key"]) { paths in
            let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: useArtifact)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let fq = ["kotlin", "collections", "Map", "Entry"].map(ctx.interner.intern)
            let entry = try #require(sema.symbols.lookup(fqName: fq))
            #expect(sema.types.nominalTypeParameterSymbols(for: entry).count == 2)
            #expect(sema.types.nominalTypeParameterVariances(for: entry) == [.out, .out])
            for path in [fq, fq + [ctx.interner.intern("key")], fq + [ctx.interner.intern("value")]] {
                let symbol = try #require(sema.symbols.lookup(fqName: path))
                #expect(sema.symbols.isSourceBackedSymbol(symbol))
                #expect(sema.symbols.symbol(symbol)?.flags.contains(.synthetic) == false)
                #expect(sema.symbols.externalLinkName(for: symbol) == nil)
            }
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
