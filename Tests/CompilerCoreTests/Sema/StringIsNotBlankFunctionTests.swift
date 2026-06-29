@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-029: Validates that `isNotBlank` resolves through Sema for
/// both `String` and `CharSequence` receivers, returning a non-null `Boolean`.
///
/// Both String and CharSequence receivers link to the flattened String ABI.
@Suite
struct StringIsNotBlankFunctionTests {
    @Test func testIsNotBlankFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stringHasContent(value: String): Boolean {
            return value.isNotBlank()
        }

        fun charSequenceHasContent(value: CharSequence): Boolean {
            return value.isNotBlank()
        }

        fun literalHasContent(): Boolean {
            return "hello".isNotBlank()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isNotBlank to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIsNotBlankStringExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "isNotBlank"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.text.isNotBlank to be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_isNotBlank",
            "Expected isNotBlank extension to link to kk_string_isNotBlank"
        )
    }
}
