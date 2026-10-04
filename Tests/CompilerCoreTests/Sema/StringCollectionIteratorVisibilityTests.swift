@testable import CompilerCore
import Testing

/// SLOP-010: the source-backed CharSequence iterator is an implementation
/// detail, while the public conversion and iteration extensions remain usable.
@Suite
struct StringCollectionIteratorVisibilityTests {
    @Test
    func testCharSequenceIteratorIsPrivateAndOldNameIsAbsent() throws {
        let ctx = makeContextFromSource("""
        fun countCharacters(value: CharSequence): Int {
            var count = 0
            for (character in value) {
                count++
            }
            return count + value.toList().size + value.asIterable().toList().size + value.asSequence().toList().size
        }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected CharSequence collection conversions to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let oldName = ["kotlin", "text", "Ksp409CharSequenceIterator"].map { ctx.interner.intern($0) }
        #expect(sema.symbols.lookupAll(fqName: oldName).isEmpty)

        let newName = ["kotlin", "text", "CharSequenceCharIterator"].map { ctx.interner.intern($0) }
        let iteratorSymbol = try #require(sema.symbols.lookup(fqName: newName))
        let symbol = try #require(sema.symbols.symbol(iteratorSymbol))
        #expect(symbol.kind == .class)
        #expect(symbol.visibility == .private)
        #expect(sema.symbols.externalLinkName(for: iteratorSymbol) == nil)
    }
}
