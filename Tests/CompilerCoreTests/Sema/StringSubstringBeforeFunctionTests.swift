@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-076: Validates that `String.substringBefore(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes four overloads:
///   String.substringBefore(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringBefore(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures and accepts an
/// optional `missingDelimiterValue` parameter. These tests pin down each shape so future
/// refactors of the synthetic stub registry don't accidentally regress overload resolution.
@Suite
struct StringSubstringBeforeFunctionTests {
    @Test func testSubstringBeforeStringDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun firstSegment(path: String): String {
            return path.substringBefore(".")
        }

        fun explicitFallback(path: String): String {
            return path.substringBefore(".", "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBefore(String[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeCharDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun firstSegment(path: String): String {
            return path.substringBefore('.')
        }

        fun explicitFallback(path: String): String {
            return path.substringBefore('.', "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBefore(Char[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeOnLiteralReceiverResolves() throws {
        let ctx = makeContextFromSource("""
        fun useLiteral(): String = "hello.world.kt".substringBefore(".")
        fun useLiteralChar(): String = "hello.world.kt".substringBefore('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringBefore(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringBefore(':', "<absent>")
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected substringBefore on literal receivers to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    @Test func testSubstringBeforeNamedArgumentResolves() throws {
        let ctx = makeContextFromSource("""
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
            "Expected named-argument substringBefore to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
