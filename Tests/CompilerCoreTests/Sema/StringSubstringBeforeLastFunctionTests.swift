@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-077: Validates that `String.substringBeforeLast(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes two overloads (each with an optional `missingDelimiterValue` defaulting to `this`):
///   String.substringBeforeLast(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringBeforeLast(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures. These tests pin down
/// each shape — including literal receivers and named arguments — so future refactors of the
/// synthetic stub registry don't accidentally regress overload resolution. Mirrors the
/// substringBefore (FN-076) and substringAfterLast (FN-075) suites.
@Suite
struct StringSubstringBeforeLastFunctionTests {
    @Test func testSubstringBeforeLastStringDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun headSegment(path: String): String {
            return path.substringBeforeLast(".")
        }

        fun explicitFallback(path: String): String {
            return path.substringBeforeLast(".", "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBeforeLast(String[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeLastCharDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun headSegment(path: String): String {
            return path.substringBeforeLast('.')
        }

        fun explicitFallback(path: String): String {
            return path.substringBeforeLast('.', "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBeforeLast(Char[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeLastOnLiteralReceiverResolves() throws {
        let ctx = makeContextFromSource("""
        fun useLiteral(): String = "hello.world.kt".substringBeforeLast(".")
        fun useLiteralChar(): String = "hello.world.kt".substringBeforeLast('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringBeforeLast(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringBeforeLast(':', "<absent>")
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBeforeLast on literal receivers to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeLastNamedArgumentResolves() throws {
        let ctx = makeContextFromSource("""
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
            "Expected named-argument substringBeforeLast to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
