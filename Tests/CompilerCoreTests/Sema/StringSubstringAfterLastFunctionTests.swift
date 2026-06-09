@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-075: Validates that `String.substringAfterLast(delimiter, missingDelimiterValue)`
/// resolves through Sema for every Kotlin-published overload.
///
/// Kotlin exposes two overloads (each with an optional `missingDelimiterValue` defaulting to `this`):
///   String.substringAfterLast(delimiter: Char,   missingDelimiterValue: String = this): String
///   String.substringAfterLast(delimiter: String, missingDelimiterValue: String = this): String
///
/// The Sema layer registers both `Char` and `String` delimiter signatures. These tests pin down
/// each shape — including literal receivers and named arguments — so future refactors of the
/// synthetic stub registry don't accidentally regress overload resolution.
final class StringSubstringAfterLastFunctionTests: XCTestCase {
    func testSubstringAfterLastStringDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun lastSegment(path: String): String {
            return path.substringAfterLast(".")
        }

        fun explicitFallback(path: String): String {
            return path.substringAfterLast(".", "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected substringAfterLast(String[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSubstringAfterLastCharDelimiterResolves() throws {
        let ctx = makeContextFromSource("""
        fun lastSegment(path: String): String {
            return path.substringAfterLast('.')
        }

        fun explicitFallback(path: String): String {
            return path.substringAfterLast('.', "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected substringAfterLast(Char[, String]) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSubstringAfterLastOnLiteralReceiverResolves() throws {
        let ctx = makeContextFromSource("""
        fun useLiteral(): String = "hello.world.kt".substringAfterLast(".")
        fun useLiteralChar(): String = "hello.world.kt".substringAfterLast('.')
        fun useLiteralWithFallback(): String = "no-delimiter".substringAfterLast(":", "<absent>")
        fun useLiteralCharWithFallback(): String = "no-delimiter".substringAfterLast(':', "<absent>")
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected substringAfterLast on literal receivers to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testSubstringAfterLastNamedArgumentResolves() throws {
        let ctx = makeContextFromSource("""
        fun useNamedString(path: String): String {
            return path.substringAfterLast(delimiter = ".", missingDelimiterValue = "<none>")
        }

        fun useNamedChar(path: String): String {
            return path.substringAfterLast(delimiter = '.', missingDelimiterValue = "<none>")
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected named-argument substringAfterLast to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
