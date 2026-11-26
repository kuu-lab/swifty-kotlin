#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct CollectionHOFManifestDecodeErrorTests {

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            """
            package sample0

                    fun test(values: List<String>) {
                        values.mapIndexed { i, s -> s }
                        values.groupBy { it.length }
                        values.partition { it.length > 3 }
                    }

            """,
            """
            package sample1

                    fun test(values: List<Int>) {
                        values.windowed(3, 2, true) { window ->
                            window.size
                        }
                    }

            """,
            """
            package sample2
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            _ = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            do {

                let sample0Path = paths[0]



                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let collectionsFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]

                let mapIndexedSource = sema.symbols.lookup(
                    fqName: collectionsFQ + [interner.intern("mapIndexed")]
                )
                #expect(mapIndexedSource != nil, "mapIndexed bundled source must exist without external metadata")
                if let mapIndexedSource {
                    let symbol = try #require(sema.symbols.symbol(mapIndexedSource))
                    #expect(!symbol.flags.contains(.synthetic), "mapIndexed must be a real bundled source declaration")
                }

                let partitionSymbolID = sema.symbols.lookup(
                    fqName: collectionsFQ + [interner.intern("partition")]
                )
                #expect(partitionSymbolID != nil, "Bundled source for 'partition' must exist without external metadata")
                if let partitionSymbolID {
                    let partitionSymbol = try #require(sema.symbols.symbol(partitionSymbolID))
                    #expect(!partitionSymbol.flags.contains(.synthetic), "partition must be a real bundled source declaration")
                    #expect(sema.symbols.externalLinkName(for: partitionSymbolID) == nil)
                }

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)

            }

            do {

                let sample1Path = paths[1]



                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let collectionsFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]
                let windowedCandidates = sema.symbols.lookupAll(
                    fqName: collectionsFQ + [interner.intern("windowed")]
                )
                let windowedTransform = windowedCandidates.first { symID in
                    guard let sig = sema.symbols.functionSignature(for: symID) else {
                        return false
                    }
                    return sig.parameterTypes.count == 4
                }

                #expect(windowedTransform != nil, "Bundled source for Iterable.windowed(size, step, partialWindows, transform) must exist")
                if let windowedTransform {
                    #expect(sema.symbols.externalLinkName(for: windowedTransform) == nil)
                    let fileID = try #require(sema.symbols.sourceFileID(for: windowedTransform))
                    #expect(ctx.sourceManager.path(of: fileID) == "__bundled_kotlin/collections/ListWindowChunk.kt")
                }

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)

            }

            do {




                let collectionsFQ: [InternedString] = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                ]

                let hofMembers = [
                    "mapIndexed", "flatMap", "associate",
                    "associateBy", "associateWith",
                    "groupBy", "partition",
                ]

                for memberName in hofMembers {
                    let symbolIDs = sema.symbols.lookupAll(
                        fqName: collectionsFQ + [interner.intern(memberName)]
                    )
                    #expect(!symbolIDs.isEmpty, "Expected bundled source declaration for '\(memberName)'")
                    for symbolID in symbolIDs {
                        let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                        #expect(!flags.contains(.synthetic), "Expected '\(memberName)' to be backed by bundled Kotlin source")
                        #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
                    }
                }

            }

        }
    }

}

#endif
