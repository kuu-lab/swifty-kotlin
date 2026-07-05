@testable import CompilerCore
import Testing

@Suite
struct SequenceWindowChunkSourceMigrationTests {
    @Test
    func migratedSequenceWindowChunkFunctionsAreBundledSourceDefinitions() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let packageFQName = ["kotlin", "sequences"].map(ctx.interner.intern)
        let expectedArities: [String: Set<Int>] = [
            "take": [1],
            "takeWhile": [1],
            "drop": [1],
            "dropWhile": [1],
            "chunked": [1, 2],
            "windowed": [3, 4],
            "zip": [1, 2],
            "zipWithNext": [0, 1],
            "distinct": [0],
            "distinctBy": [1],
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
                return ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/sequences/SequenceWindowChunk.kt"
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
                "Expected \(name) bundled source definitions to be Sequence extension functions"
            )
            #expect(
                sourceSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Expected \(name) bundled source definitions to avoid direct C external links"
            )
        }
    }

    @Test
    func sequenceWindowChunkSyntheticBridgesRetainRuntimeLinks() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let sequenceFQName = ["kotlin", "sequences", "Sequence"].map(ctx.interner.intern)
        let expectedLinks: [String: String] = [
            "__kk_sequence_take": "kk_sequence_take",
            "__kk_sequence_takeWhile": "kk_sequence_takeWhile",
            "__kk_sequence_drop": "kk_sequence_drop",
            "__kk_sequence_dropWhile": "kk_sequence_dropWhile",
            "__kk_sequence_chunked": "kk_sequence_chunked",
            "__kk_sequence_chunked_transform": "kk_sequence_chunked_transform",
            "__kk_sequence_windowed": "kk_sequence_windowed",
            "__kk_sequence_windowed_transform": "kk_sequence_windowed_transform",
            "__kk_sequence_zip": "kk_sequence_zip",
            "__kk_sequence_zip_transform": "kk_sequence_zip_transform",
            "__kk_sequence_zipWithNext": "kk_sequence_zipWithNext",
            "__kk_sequence_zipWithNextTransform": "kk_sequence_zipWithNextTransform",
            "__kk_sequence_distinct": "kk_sequence_distinct",
            "__kk_sequence_distinctBy": "kk_sequence_distinctBy",
        ]

        for (name, expectedLink) in expectedLinks {
            let fqName = sequenceFQName + [ctx.interner.intern(name)]
            let links = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            #expect(links.contains(expectedLink), "Expected \(name) bridge to link to \(expectedLink)")
        }
    }

    @Test
    func migratedSequenceWindowChunkFunctionsDoNotKeepPublicRuntimeLinkedMembers() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let sequenceFQName = ["kotlin", "sequences", "Sequence"].map(ctx.interner.intern)
        let disallowedMemberLinks: [String: Set<String>] = [
            "take": ["kk_sequence_take"],
            "takeWhile": ["kk_sequence_takeWhile"],
            "drop": ["kk_sequence_drop"],
            "dropWhile": ["kk_sequence_dropWhile"],
            "chunked": ["kk_sequence_chunked", "kk_sequence_chunked_transform"],
            "windowed": ["kk_sequence_windowed", "kk_sequence_windowed_transform"],
            "zip": ["kk_sequence_zip", "kk_sequence_zip_transform"],
            "zipWithNext": ["kk_sequence_zipWithNext", "kk_sequence_zipWithNextTransform"],
            "distinct": ["kk_sequence_distinct"],
            "distinctBy": ["kk_sequence_distinctBy"],
        ]

        for (name, disallowedLinks) in disallowedMemberLinks {
            let fqName = sequenceFQName + [ctx.interner.intern(name)]
            let memberLinks = Set(sema.symbols.lookupAll(fqName: fqName).compactMap {
                sema.symbols.externalLinkName(for: $0)
            })
            let leakedLinks = memberLinks.intersection(disallowedLinks)
            #expect(
                leakedLinks.isEmpty,
                "Expected \(name) to be served by bundled source, but found public member links \(leakedLinks)"
            )
        }

        let oldZipWithNextTransformFQName = sequenceFQName
            + [ctx.interner.intern("zipWithNext"), ctx.interner.intern("transform")]
        let oldZipWithNextTransformLinks = Set(
            sema.symbols.lookupAll(fqName: oldZipWithNextTransformFQName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
        #expect(
            !oldZipWithNextTransformLinks.contains("kk_sequence_zipWithNextTransform"),
            "Expected zipWithNext(transform) to be served by bundled source"
        )
    }
}
