@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-037: Validates that `CharSequence.lines()` resolves through
/// Sema on String receivers through bundled Kotlin source, returning `List<String>`.
@Suite
struct StringLinesFunctionTests {
    @Test func testLinesResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun splitToLines(s: String): List<String> {
            return s.lines()
        }

        fun firstLine(): String {
            return "a\\nb\\nc".lines().first()
        }

        fun printAll(s: String) {
            for (line in s.lines()) {
                println(line)
            }
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected lines to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
