@testable import CompilerCore
import Testing

/// KSP-946/KSP-703: MutableMap's nominal declaration is source-backed while
/// its runtime-backed mutation surface retains direct ABI links.
@Suite
struct MutableMapInterfaceSourceMigrationTests {
    @Test
    func mutableMapInterfaceUsesSourceDeclarationWithTargetVariance() throws {
        let ctx = makeContextFromSource(
            """
            fun probe(values: MutableMap<String, Int>): MutableMap<String, Int> = values
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mutableMapFQName = ["kotlin", "collections", "MutableMap"].map(interner.intern)
        let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: mutableMapFQName))
        let mutableMapInfo = try #require(sema.symbols.symbol(mutableMapSymbol))
        #expect(mutableMapInfo.kind == .interface)
        #expect(!mutableMapInfo.flags.contains(.synthetic))

        let sourceFile = try #require(sema.symbols.sourceFileID(for: mutableMapSymbol))
        #expect(ctx.sourceManager.path(of: sourceFile) == "__bundled_kotlin/collections/MutableMap.kt")
        #expect(sema.types.nominalTypeParameterVariances(for: mutableMapSymbol) == [.invariant, .invariant])

        let typeParameters = sema.types.nominalTypeParameterSymbols(for: mutableMapSymbol)
        #expect(typeParameters.count == 2)
        #expect(sema.symbols.symbol(typeParameters[0])?.name == interner.intern("K"))
        #expect(sema.symbols.symbol(typeParameters[1])?.name == interner.intern("V"))

        let mapSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern))
        )
        #expect(sema.symbols.directSupertypes(for: mutableMapSymbol) == [mapSymbol])
    }

    /// `MutableMap` must override `keys`/`values` with the mutable
    /// covariant types (`MutableSet<K>` / `MutableCollection<V>`), matching
    /// real Kotlin's `MutableMap<K, V>` declaration. Before this fix they
    /// fell through to `Map`'s read-only `Set<K>` / `Collection<V>`, so
    /// `MutableMap<K, V>`-typed receivers (e.g. `mutableMapOf(...)`'s return
    /// type) rejected `keys.remove()` / `values.remove()` / `keys.clear()`
    /// with "Unresolved member function" even though the equivalent
    /// `entries` override already worked.
    @Test
    func mutableMapOverridesKeysAndValuesWithMutableCovariantTypes() throws {
        let ctx = makeContextFromSource(
            """
            fun probe(values: MutableMap<String, Int>): MutableMap<String, Int> = values
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let types = sema.types
        let mutableMapFQName = ["kotlin", "collections", "MutableMap"].map(interner.intern)
        let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: mutableMapFQName))

        let typeParameters = types.nominalTypeParameterSymbols(for: mutableMapSymbol)
        #expect(typeParameters.count == 2)
        let keyType = types.make(.typeParam(TypeParamType(symbol: typeParameters[0], nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: typeParameters[1], nullability: .nonNull)))

        func property(named name: String) throws -> SymbolID {
            try #require(
                sema.symbols.lookupAll(fqName: mutableMapFQName + [interner.intern(name)]).first {
                    sema.symbols.symbol($0)?.kind == .property
                        && sema.symbols.parentSymbol(for: $0) == mutableMapSymbol
                },
                "Missing MutableMap.\(name)"
            )
        }

        let mutableSetSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "MutableSet"].map(interner.intern))
        )
        let mutableCollectionSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlin", "collections", "MutableCollection"].map(interner.intern))
        )

        let keysSymbol = try property(named: "keys")
        #expect(sema.symbols.externalLinkName(for: keysSymbol) == "__kk_map_keys")
        let expectedKeysType = types.make(.classType(ClassType(
            classSymbol: mutableSetSymbol,
            args: [.invariant(keyType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: keysSymbol) == expectedKeysType)

        let valuesSymbol = try property(named: "values")
        #expect(sema.symbols.externalLinkName(for: valuesSymbol) == "__kk_map_values")
        let expectedValuesType = types.make(.classType(ClassType(
            classSymbol: mutableCollectionSymbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: valuesSymbol) == expectedValuesType)
    }

    @Test
    func mutableMapRetainsResidualMutationMemberLinks() throws {
        let ctx = makeContextFromSource(
            """
            fun mutate(values: MutableMap<String, Int>): MutableMap<String, Int> {
                values["present"] = 1
                values.put("present", 2)
                values.remove("missing")
                values.clear()
                return values
            }
            """
        )
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let mutableMapFQName = ["kotlin", "collections", "MutableMap"].map(interner.intern)
        let mutableMapSymbol = try #require(sema.symbols.lookup(fqName: mutableMapFQName))
        let expectedLinks: [(name: String, link: String)] = [
            ("put", "__kk_mutable_map_put"),
            ("remove", "__kk_mutable_map_remove"),
            ("clear", "__kk_mutable_map_clear"),
        ]
        for expected in expectedLinks {
            let memberFQName = mutableMapFQName + [interner.intern(expected.name)]
            let memberSymbol = try #require(sema.symbols.lookup(fqName: memberFQName))
            #expect(sema.symbols.parentSymbol(for: memberSymbol) == mutableMapSymbol)
            #expect(sema.symbols.externalLinkName(for: memberSymbol) == expected.link)
        }
    }
}
