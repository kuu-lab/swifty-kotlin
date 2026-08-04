@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-076: Validates that `String.substringBefore(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes two overloads (each with an optional `missingDelimiterValue` defaulting to `this`):
///   String.substringBefore(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringBefore(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures.
@Suite
struct StringSubstringBeforeFunctionTests {
    @Test func testSubstringBeforeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun firstSegmentString(path: String): String {
            return path.substringBefore(".")
        }

        fun explicitFallbackString(path: String): String {
            return path.substringBefore(".", "<none>")
        }

        fun firstSegmentChar(path: String): String {
            return path.substringBefore('.')
        }

        fun explicitFallbackChar(path: String): String {
            return path.substringBefore('.', "<none>")
        }

        fun useLiteral(): String = "hello.world.kt".substringBefore(".")
        fun useLiteralChar(): String = "hello.world.kt".substringBefore('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringBefore(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringBefore(':', "<absent>")

        fun useNamedString(path: String): String {
            return path.substringBefore(delimiter = ".", missingDelimiterValue = "<none>")
        }

        fun useNamedChar(path: String): String {
            return path.substringBefore(delimiter = '.', missingDelimiterValue = "<none>")
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBefore overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
