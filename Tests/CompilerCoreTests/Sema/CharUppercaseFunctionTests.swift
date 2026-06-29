#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-PROP-022: Validates that `Char.uppercase()` resolves through Sema
/// across its public surface: the no-arg overload returning `String`, the
/// `Locale`-aware overload, and the related `uppercaseChar()` returning `Char`.
/// Runtime link names involved: `kk_char_uppercase`, `kk_char_uppercase_locale`,
/// `kk_char_uppercaseChar`.
@Suite
struct CharUppercaseFunctionTests {
    @Test func testCharUppercaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import java.util.Locale

        fun upperAscii(): String = 'a'.uppercase()

        fun upperUnicode(): String = '\u{00DF}'.uppercase()

        fun upperChar(ch: Char): Char = ch.uppercaseChar()

        fun upperWithLocale(ch: Char): String {
            val locale = Locale("en", "US")
            return ch.uppercase(locale)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Char.uppercase to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
