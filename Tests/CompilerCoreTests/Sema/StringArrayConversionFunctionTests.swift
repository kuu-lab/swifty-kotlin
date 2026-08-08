@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-014/092/093/109: Consolidated Sema coverage for
/// `String.encodeToByteArray`, `String.toByteArray`, `String.toCharArray`, and
/// `String.toTypedArray` overloads. A single `runSema(ctx)` resolves all source
/// packages and each package is checked for the absence of errors.
@Suite
struct StringArrayConversionFunctionTests {
    @Test
    func testStringArrayConversionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0

            fun encode(s: String): ByteArray = s.encodeToByteArray()

            fun encodeLiteral(): ByteArray = "hello".encodeToByteArray()

            fun encodeSlice(s: String): ByteArray = s.encodeToByteArray(1, 4)

            fun encodeLiteralSlice(): ByteArray = "abcdef".encodeToByteArray(0, 3)

            fun encodeWithCharset(s: String): ByteArray = s.encodeToByteArray(Charsets.UTF_8)

            fun encodeAscii(s: String): ByteArray = s.encodeToByteArray(Charsets.US_ASCII)

            fun roundTrip(s: String): String = s.encodeToByteArray().decodeToString()
            """,
            """
            package sample1

            fun getBytes(s: String): ByteArray = s.toByteArray()

            fun getLiteralBytes(): ByteArray = "hello".toByteArray()

            fun getUtf8Bytes(s: String): ByteArray = s.toByteArray(Charsets.UTF_8)
            fun getAsciiBytes(s: String): ByteArray = s.toByteArray(Charsets.US_ASCII)
            fun getLatin1Bytes(s: String): ByteArray = s.toByteArray(Charsets.ISO_8859_1)

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

            fun byteCount(s: String): Int {
                return s.toByteArray().size
            }
            """,
            """
            package sample2

            fun explodeToCharArray(s: String): CharArray {
                return s.toCharArray()
            }

            fun explodeCharArrayLiteral(): CharArray {
                return "hello".toCharArray()
            }

            fun countChars(s: String): Int {
                return s.toCharArray().size
            }

            fun firstChar(s: String): Char {
                return s.toCharArray()[0]
            }

            fun explodeToTypedArray(s: String): Array<Char> {
                return s.toTypedArray()
            }

            fun explodeTypedArrayLiteral(): Array<Char> {
                return "hello".toTypedArray()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let names = [
                "encodeToByteArray",
                "toByteArray",
                "toCharArray / toTypedArray",
            ]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }
        }
    }
}
