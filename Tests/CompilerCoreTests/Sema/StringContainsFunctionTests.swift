@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-012: Validates that `CharSequence.contains` resolves through
/// Sema for `String` receivers across all of its stdlib overloads. The synthetic
/// stubs register:
/// - `contains(other: String)` → `kk_string_contains_str_flat` (also acts as the
///   `in` operator on strings).
/// - `contains(other: String, ignoreCase: Boolean)` → `kk_string_contains_ignoreCase_flat`
/// - `contains(regex: Regex)` -> `kk_string_contains_regex_flat`
@Suite
struct StringContainsFunctionTests {
    @Test func testContainsResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstring(s: String): Boolean {
            return s.contains("hello")
        }

        fun emptyNeedleAlwaysMatches(s: String): Boolean {
            return s.contains("")
        }

        fun literalReceiverContains(): Boolean {
            return "hello world".contains("world")
        }

        fun hasSubstringIgnoreCase(s: String): Boolean {
            return s.contains("HELLO", true)
        }

        fun explicitCaseSensitive(s: String, needle: String): Boolean {
            return s.contains(needle, false)
        }

        fun namedIgnoreCase(s: String): Boolean {
            return s.contains("foo", ignoreCase = true)
        }

        fun substringViaInOperator(s: String, needle: String): Boolean {
            return needle in s
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let containsFQName: [InternedString] = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("text"),
            ctx.interner.intern("contains"),
        ]

        let resolvedSymbols = sema.symbols.lookupAll(fqName: containsFQName)
        let externalLinks = Set(resolvedSymbols.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(externalLinks.contains("kk_string_contains_str_flat"))
        #expect(
            externalLinks.contains("kk_string_contains_ignoreCase_flat"),
            "Expected a `kotlin.text/contains` symbol to expose externalLinkName=kk_string_contains_ignoreCase_flat"
        )
    }
}
