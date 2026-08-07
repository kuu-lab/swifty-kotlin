@testable import CompilerCore
import Testing

/// KSP-408: Validates that `CharSequence.contains` resolves through Sema for
/// `String` receivers across all of its stdlib overloads (bundled Kotlin source,
/// `StringIndexOf.kt`), including the `in` operator and the case-insensitive
/// overload. `contains(regex: Regex)` remains a separate synthetic stub.
@Suite
struct StringContainsFunctionTests {
    @Test func testContainsWithStringResolvesInSource() throws {
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
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected contains(String) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testContainsWithIgnoreCaseResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun hasSubstringIgnoreCase(s: String): Boolean {
            return s.contains("HELLO", true)
        }

        fun explicitCaseSensitive(s: String, needle: String): Boolean {
            return s.contains(needle, false)
        }

        fun namedIgnoreCase(s: String): Boolean {
            return s.contains("foo", ignoreCase = true)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected contains(String, Boolean) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testContainsInOperatorResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun substringViaInOperator(s: String, needle: String): Boolean {
            return needle in s
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected `in` operator on String to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

}
