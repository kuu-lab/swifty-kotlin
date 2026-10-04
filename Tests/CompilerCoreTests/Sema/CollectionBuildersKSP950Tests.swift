#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-950: the complete build-family surface is owned by CollectionBuilders.kt.
/// The public overloads and their @PublishedApi internal counterparts must not
/// be replaced by residual synthetic declarations.
@Suite
struct CollectionBuildersKSP950Tests {
    @Test
    func buildFamilyHasSourceBackedPublicAndInternalOverloads() throws {
        let ctx = makeContextFromSource("fun useBuilders() = buildList { add(1) }")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let sourcePath = "__bundled_kotlin/collections/CollectionBuilders.kt"
        let expected: [(name: String, visibility: Visibility)] = [
            ("buildList", .public),
            ("buildSet", .public),
            ("buildMap", .public),
            ("buildListInternal", .internal),
            ("buildSetInternal", .internal),
            ("buildMapInternal", .internal),
        ]

        for item in expected {
            let sourceSymbols = sema.symbols.lookupAll(
                fqName: packageFQName + [ctx.interner.intern(item.name)]
            ).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == sourcePath
            }

            #expect(sourceSymbols.count == 2, "Expected two (item.name) overloads")
            #expect(sourceSymbols.allSatisfy { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                return symbol.visibility == item.visibility
                    && !symbol.flags.contains(.synthetic)
                    && sema.symbols.isSourceBackedSymbol(symbolID)
                    && sema.symbols.externalLinkName(for: symbolID) == nil
            })
            #expect(sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0) != nil })
        }
    }
}
#endif
