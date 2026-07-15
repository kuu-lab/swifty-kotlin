#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ListWindowChunkSourceMigrationTests {
    @Test
    func migratedListWindowChunkFunctionsAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "collections"].map(ctx.interner.intern)
        let expectedArities: [String: Set<Int>] = [
            "chunked": [1, 2],
            "windowed": [3, 4],
            "zip": [1, 2],
            "zipWithNext": [0, 1],
            "withIndex": [0],
        ]

        for (name, arities) in expectedArities {
            let fqName = packageFQName + [ctx.interner.intern(name)]
            let sourceSymbols = sema.symbols.lookupAll(fqName: fqName).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID),
                      symbol.kind == .function,
                      !symbol.flags.contains(.synthetic),
                      let fileID = sema.symbols.sourceFileID(for: symbolID)
                else {
                    return false
                }
                return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt"
            }
            let registeredArities = Set(sourceSymbols.compactMap { symbolID in
                sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count
            })

            #expect(
                arities.isSubset(of: registeredArities),
                "Expected \(name) bundled source overloads \(arities), got \(registeredArities)"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.functionSignature(for: $0)?.receiverType != nil },
                "Expected \(name) bundled source definitions to be extension functions"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Expected \(name) bundled source definitions to avoid direct C external links"
            )
        }
    }

    @Test
    func migratedListWindowChunkFunctionsDoNotKeepPublicRuntimeLinkedMembers() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let listFQName = ["kotlin", "collections", "List"].map(ctx.interner.intern)
        let iterableFQName = ["kotlin", "collections", "Iterable"].map(ctx.interner.intern)
        let disallowedMemberLinks: [(owner: [InternedString], name: String, links: Set<String>)] = [
            (listFQName, "chunked", ["kk_list_chunked", "kk_list_chunked_transform"]),
            (iterableFQName, "windowed", [
                "kk_list_windowed",
                "kk_list_windowed_default",
                "kk_list_windowed_partial",
                "kk_list_windowed_transform",
            ]),
            (listFQName, "windowed", [
                "kk_list_windowed",
                "kk_list_windowed_default",
                "kk_list_windowed_partial",
                "kk_list_windowed_transform",
            ]),
            (listFQName, "zip", ["kk_list_zip"]),
            (listFQName, "zipWithNext", ["kk_list_zipWithNext", "kk_list_zipWithNextTransform"]),
        ]

        for (owner, name, disallowedLinks) in disallowedMemberLinks {
            let fqName = owner + [ctx.interner.intern(name)]
            let memberLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            let leakedLinks = memberLinks.intersection(disallowedLinks)
            #expect(
                leakedLinks.isEmpty,
                "Expected \(name) to be served by bundled source, but found public member links \(leakedLinks)"
            )
        }
    }
}
#endif
