@testable import CompilerCore
import RuntimeABI
import Testing

@Suite
struct IterableIteratorSourceMigrationTests {
    @Test func iteratorHasSourceDeclarationAndThrowingBridge() throws {
        let source = """
        fun probe(values: Iterable<Int>): Iterator<Int> = values.iterator()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let fqName = ["kotlin", "collections", "Iterable", "iterator"].map(ctx.interner.intern)
            let member = try #require(sema.symbols.lookup(fqName: fqName))
            let info = try #require(sema.symbols.symbol(member))
            #expect(!info.flags.contains(.synthetic))
            #expect(info.flags.contains(.operatorFunction))
            let file = try #require(sema.symbols.sourceFileID(for: member))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/collections/Iterable.kt")
            #expect(sema.symbols.externalLinkName(for: member) == "kk_iterable_iterator")
            // KsSymbolName calls take their exception channel from RuntimeABI.
            let bridge = try #require(RuntimeABISpec.byName["kk_iterable_iterator"])
            #expect(bridge.isThrowing)
        }
    }
}
