@testable import CompilerCore
import Testing

@Suite
struct IterableIteratorSourceMigrationTests {
    @Test func iteratorHasThrowingSourceDeclaration() throws {
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
            let signature = try #require(sema.symbols.functionSignature(for: member))
            #expect(signature.canThrow)
        }
    }
}
