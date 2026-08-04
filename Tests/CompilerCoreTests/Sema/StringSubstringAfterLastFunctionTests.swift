@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-075: Validates that `String.substringAfterLast(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes two overloads (each with an optional `missingDelimiterValue` defaulting to `this`):
///   String.substringAfterLast(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringAfterLast(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures.
@Suite
struct StringSubstringAfterLastFunctionTests {
    @Test func testSubstringAfterLastResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun lastSegmentString(path: String): String {
            return path.substringAfterLast(".")
        }

        fun explicitFallbackString(path: String): String {
            return path.substringAfterLast(".", "<none>")
        }

        fun lastSegmentChar(path: String): String {
            return path.substringAfterLast('.')
        }

        fun explicitFallbackChar(path: String): String {
            return path.substringAfterLast('.', "<none>")
        }

        fun useLiteral(): String = "hello.world.kt".substringAfterLast(".")
        fun useLiteralChar(): String = "hello.world.kt".substringAfterLast('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringAfterLast(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringAfterLast(':', "<absent>")

        fun useNamedString(path: String): String {
            return path.substringAfterLast(delimiter = ".", missingDelimiterValue = "<none>")
        }

        fun useNamedChar(path: String): String {
            return path.substringAfterLast(delimiter = '.', missingDelimiterValue = "<none>")
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringAfterLast overloads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
