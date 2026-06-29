@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-030: Validates that `isNotEmpty` resolves through Sema for
/// `String` and `CharSequence` receivers, returning a non-null `Boolean`.
///
/// The runtime helper is `kk_string_isNotEmpty` and the Sema-side extension
/// stub is registered alongside `isEmpty` / `isBlank` / `isNotBlank` in
/// `HeaderHelpers+SyntheticStringStubs.swift`.
@Suite
struct StringIsNotEmptyFunctionTests {
    @Test func testIsNotEmptyFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun stringHasContent(value: String): Boolean {
            return value.isNotEmpty()
        }

        fun charSequenceHasContent(value: CharSequence): Boolean {
            return value.isNotEmpty()
        }

        fun literalHasContent(): Boolean {
            return "hello".isNotEmpty()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isNotEmpty to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIsNotEmptyStringExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "isNotEmpty"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.text.isNotEmpty to be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_isNotEmpty",
            "Expected isNotEmpty extension to link to kk_string_isNotEmpty"
        )
    }
}
