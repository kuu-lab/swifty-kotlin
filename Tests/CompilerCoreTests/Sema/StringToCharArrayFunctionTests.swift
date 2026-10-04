@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-093/109: Validates that `String.toCharArray()` and
/// `String.toTypedArray()` resolve through Sema.
@Suite
struct StringToCharArrayFunctionTests {
    @Test func testToCharArrayAndToTypedArrayResolvesInSource() throws {
        let ctx = makeContextFromSource("""
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toCharArray/toTypedArray to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
