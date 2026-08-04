@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-081: Validates that `String.takeLastWhile(predicate)` resolves
/// through Sema for `String` receivers. After KSP-405 it is bundled Kotlin source (StringTakeDrop.kt).
@Suite
struct StringTakeLastWhileFunctionTests {
    @Test func testTakeLastWhileResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun trailingLetters(s: String): String {
            return s.takeLastWhile { it.isLetter() }
        }

        fun trailDigits(): String {
            return "abc123".takeLastWhile { it.isDigit() }
        }

        fun trailingLower(s: String): String {
            return s.takeLastWhile { it.isLowerCase() }
        }

        fun trimmedSuffix(s: String): String {
            return s.trim().takeLastWhile { it != ' ' }
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
