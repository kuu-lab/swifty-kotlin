@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-027: Validates that `CharSequence.isBlank()` resolves through Sema
/// for `String` / `CharSequence` receivers, dispatching to the runtime link
/// name `kk_string_isBlank_flat`.
@Suite
struct StringIsBlankFunctionTests {
    @Test func testIsBlankFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun isStringBlank(s: String): Boolean {
            return s.isBlank()
        }

        fun isBlankLiteral(): Boolean {
            return "   ".isBlank()
        }

        fun isNonBlankLiteral(): Boolean {
            return "hello".isBlank()
        }

        fun isEmptyStringBlank(): Boolean {
            return "".isBlank()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected isBlank to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testIsBlankStringExtensionHasRuntimeLink() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let fqName = ["kotlin", "text", "isBlank"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected kotlin.text.isBlank to be registered"
        )
        #expect(
            sema.symbols.externalLinkName(for: symbol) == "kk_string_isBlank_flat",
            "Expected isBlank extension to link to kk_string_isBlank"
        )
    }
}
