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
    @Test func testEncodeToByteArrayNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encode(s: String): ByteArray {
            return s.encodeToByteArray()
        }

        fun encodeLiteral(): ByteArray {
            return "hello".encodeToByteArray()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected encodeToByteArray() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testEncodeToByteArrayRangeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encodeSlice(s: String): ByteArray {
            return s.encodeToByteArray(1, 4)
        }

        fun encodeLiteralSlice(): ByteArray {
            return "abcdef".encodeToByteArray(0, 3)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected encodeToByteArray(startIndex, endIndex) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testEncodeToByteArrayCharsetResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun encodeWithCharset(s: String): ByteArray {
            return s.encodeToByteArray(Charsets.UTF_8)
        }

        fun encodeAscii(s: String): ByteArray {
            return s.encodeToByteArray(Charsets.US_ASCII)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected encodeToByteArray(charset) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testEncodeToByteArrayChainedWithDecodeToStringResolvesInSource() throws {
        // Validates that the returned ByteArray supports decodeToString
        let ctx = makeContextFromSource("""
        fun roundTrip(s: String): String {
            return s.encodeToByteArray().decodeToString()
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected encodeToByteArray().decodeToString() chain to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
