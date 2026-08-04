@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-077: Validates that `String.substringBeforeLast(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes two overloads (each with an optional `missingDelimiterValue` defaulting to `this`):
///   String.substringBeforeLast(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringBeforeLast(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures.
@Suite
struct StringSubstringBeforeLastFunctionTests {
    @Test func testSubstringBeforeLastResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun headSegmentString(path: String): String {
            return path.substringBeforeLast(".")
        }

        fun explicitFallbackString(path: String): String {
            return path.substringBeforeLast(".", "<none>")
        }

        fun headSegmentChar(path: String): String {
            return path.substringBeforeLast('.')
        }

        fun explicitFallbackChar(path: String): String {
            return path.substringBeforeLast('.', "<none>")
        }

        fun useLiteral(): String = "hello.world.kt".substringBeforeLast(".")
        fun useLiteralChar(): String = "hello.world.kt".substringBeforeLast('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringBeforeLast(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringBeforeLast(':', "<absent>")

        fun useNamedString(path: String): String {
            return path.substringBeforeLast(delimiter = ".", missingDelimiterValue = "<none>")
        }

        fun useNamedChar(path: String): String {
            return path.substringBeforeLast(delimiter = '.', missingDelimiterValue = "<none>")
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBeforeLast overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
