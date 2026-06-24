@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-092: Validates that `String.toByteArray()` and its charset overload
/// resolve through Sema and link to the correct runtime entries.
///
/// Overloads covered:
///  - `toByteArray()` → `kk_string_toByteArray` (returns List<Int>)
///  - `toByteArray(charset: Charset)` → `kk_string_toByteArray_charset` (returns List<Int>)
///
/// The synthetic extension functions are registered in
/// `HeaderHelpers+SyntheticStringStubs.swift` (STDLIB-145/STDLIB-581), and the
/// runtime implementation lives in `Sources/Runtime/RuntimeStringStdlib.swift`.
@Suite
struct StringToByteArrayFunctionTests {
    @Test func testToByteArrayNoArgResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun getBytes(s: String) = s.toByteArray()

        fun getLiteralBytes() = "hello".toByteArray()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toByteArray() to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testToByteArrayWithCharsetResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun getUtf8Bytes(s: String) = s.toByteArray(Charsets.UTF_8)

        fun getAsciiBytes(s: String) = s.toByteArray(Charsets.US_ASCII)

        fun getLatin1Bytes(s: String) = s.toByteArray(Charsets.ISO_8859_1)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toByteArray(charset) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testToByteArrayAllCharsetsResolveInSource() throws {
        let ctx = makeContextFromSource("""
        fun totalBytes(s: String): Int {
            val a = s.toByteArray(Charsets.UTF_8).size
            val b = s.toByteArray(Charsets.ISO_8859_1).size
            val c = s.toByteArray(Charsets.US_ASCII).size
            val d = s.toByteArray(Charsets.UTF_16).size
            val e = s.toByteArray(Charsets.UTF_16BE).size
            val f = s.toByteArray(Charsets.UTF_16LE).size
            val g = s.toByteArray(Charsets.UTF_32).size
            val h = s.toByteArray(Charsets.UTF_32BE).size
            val i = s.toByteArray(Charsets.UTF_32LE).size
            return a + b + c + d + e + f + g + h + i
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected all Charsets variants to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testToByteArraySizeAccessResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun byteCount(s: String): Int {
            return s.toByteArray().size
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toByteArray().size to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
