@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-094: Validates that `CharSequence.toCollection(destination)`
/// resolves through Sema and preserves the destination collection type.
@Suite
struct StringToCollectionFunctionTests {
    @Test func testToCollectionReturnsDestinationTypeForStringAndCharSequence() throws {
        let ctx = makeContextFromSource("""
        fun collectString(s: String): MutableList<Char> {
            val destination = mutableListOf<Char>('z')
            return s.toCollection(destination)
        }

        fun collectCharSequence(s: CharSequence): MutableList<Char> {
            val destination = mutableListOf<Char>()
            return s.toCollection(destination)
        }

        fun collectSet(s: String): MutableSet<Char> {
            val destination = mutableSetOf<Char>()
            return s.toCollection(destination)
        }

        fun chainedSize(s: String): Int {
            return s.toCollection(mutableListOf<Char>()).size
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected CharSequence.toCollection to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testToCollectionSyntheticLinkRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let fqName = ["kotlin", "text", "toCollection"].map { ctx.interner.intern($0) }
        let links = Set(
            sema.symbols.lookupAll(fqName: fqName)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )

        #expect(
            links.contains("kk_string_toCollection_flat"),
            "CharSequence.toCollection should link to kk_string_toCollection"
        )
    }
}
