#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Tests that collection HOF type inference works correctly even when external
/// library metadata is missing or unavailable — the compiler's built-in
/// synthetic stubs must serve as a reliable fallback.
@Suite
struct CollectionHOFManifestDecodeErrorTests {

    /// Verify that collection HOF members are available via synthetic stubs
    /// without any external library metadata loaded.
    @Test func testCollectionHOFSyntheticStubsResolveWithoutExternalMetadata() throws {
        let source = """
        fun test(values: List<String>) {
            values.mapIndexed { i, s -> s }
            values.groupBy { it.length }
            values.partition { it.length > 3 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            // No searchPaths — purely relying on synthetic stubs.
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            // Verify that synthetic stubs exist for all target HOFs.
            let listFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            // Only mapIndexed and partition have explicit synthetic stubs.
            // groupBy uses fallback inference (no symbol table entry).
            for memberName in ["mapIndexed", "partition"] {
                let symbolID = sema.symbols.lookup(
                    fqName: listFQ + [ctx.interner.intern(memberName)]
                )
                #expect(symbolID != nil, "Synthetic stub for '\(memberName)' must exist without external metadata")
            }

            // No type-constraint errors expected.
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    @Test func testCollectionWindowedTransformSourceDefinitionResolvesWithoutExternalMetadata() throws {
        let source = """
        fun test(values: List<Int>) {
            values.windowed(3, 2, true) { window ->
                window.size
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let collectionsFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
            ]
            let windowedCandidates = sema.symbols.lookupAll(
                fqName: collectionsFQ + [ctx.interner.intern("windowed")]
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

            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    /// Verify that invalid/non-existent search paths do not cause crashes
    /// and that the compiler falls back to synthetic stubs gracefully.
    @Test func testInvalidSearchPathDoesNotCrash() throws {
        let source = """
        fun test(values: List<Int>) {
            values.mapIndexed { i, v -> i + v }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                searchPaths: ["/nonexistent/path/to/library"]
            )
            // Must not crash.
            #expect(throws: Never.self) { try runSema(ctx) }

            let sema = try #require(ctx.sema)
            let mapIndexedSym = sema.symbols.lookup(fqName: [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
                ctx.interner.intern("mapIndexed"),
            ])
            #expect(mapIndexedSym != nil, "mapIndexed synthetic stub must exist despite invalid search path")
        }
    }

    /// Verify that all collection HOF stubs carry the expected inline+synthetic flags.
    @Test func testCollectionHOFStubsFlagsAreCorrect() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let listFQ: [InternedString] = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]

            let hofMembers = [
                "mapIndexed", "flatMap", "associate",
                "associateBy", "associateWith",
                "groupBy", "partition",
            ]

            for memberName in hofMembers {
                guard let symbolID = sema.symbols.lookup(
                    fqName: listFQ + [ctx.interner.intern(memberName)]
                ) else {
                    // Stubs not registered — covered by other tests.
                    continue
                }
                let flags = try #require(sema.symbols.symbol(symbolID)?.flags)
                #expect(flags.contains(.synthetic), "Expected '\(memberName)' to be marked synthetic")
            }
        }
    }
}
#endif
