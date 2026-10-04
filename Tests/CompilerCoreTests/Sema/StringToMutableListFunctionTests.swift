@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-104: Validates that `String.toMutableList()` resolves through
/// Sema and resolves to the bundled Kotlin implementation.
@Suite
struct StringToMutableListFunctionTests {
    @Test
    func testToMutableListResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun explode(s: String): MutableList<Char> {
            return s.toMutableList()
        }

        fun explodeLiteral(): MutableList<Char> {
            return "hello".toMutableList()
        }

        fun appendBang(s: String): Int {
            val chars = s.toMutableList()
            chars.add('!')
            return chars.size
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected toMutableList to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
