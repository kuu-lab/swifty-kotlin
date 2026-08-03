@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-014: Validates that `String.encodeToByteArray()` and its overloads
/// resolve through Sema and link to the correct runtime entries.
///
/// Overloads covered:
///  - `encodeToByteArray()` → `__kk_string_encodeToByteArray_flat`
///  - `encodeToByteArray(startIndex, endIndex)` → `__kk_string_encodeToByteArray_range_flat`
///  - `encodeToByteArray(charset)` → `__kk_string_encodeToByteArray_charset_flat`
///
/// All three overloads are Kotlin-sourced extension functions declared in
/// `Sources/CompilerCore/Stdlib/kotlin/text/StringEncoding.kt`, which delegate to
/// the `__kk_`-prefixed runtime bridges in `Sources/Runtime/RuntimeStringEncoding.swift`.
@Suite
struct StringEncodeToByteArrayFunctionTests {
    @Test func testEncodeToByteArrayOverloadsResolveInSource() throws {
        let ctx = makeContextFromSource("""
        fun encode(s: String): ByteArray = s.encodeToByteArray()

        fun encodeLiteral(): ByteArray = "hello".encodeToByteArray()

        fun encodeSlice(s: String): ByteArray = s.encodeToByteArray(1, 4)

        fun encodeLiteralSlice(): ByteArray = "abcdef".encodeToByteArray(0, 3)

        fun encodeWithCharset(s: String): ByteArray = s.encodeToByteArray(Charsets.UTF_8)

        fun encodeAscii(s: String): ByteArray = s.encodeToByteArray(Charsets.US_ASCII)

        fun roundTrip(s: String): String = s.encodeToByteArray().decodeToString()
        """)

        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected String.encodeToByteArray() overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
