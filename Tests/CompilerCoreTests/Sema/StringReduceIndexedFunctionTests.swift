@testable import CompilerCore
import XCTest

/// STDLIB-TEXT-FN-047: Validates that `CharSequence.reduceIndexed` resolves
/// through Sema for `String` receivers.
/// The lambda receives `(index: Int, acc: Char, c: Char) -> Char` and the
/// call must bind to the runtime link `kk_string_reduceIndexed`.
final class StringReduceIndexedFunctionTests: XCTestCase {
    func testReduceIndexedFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        fun foldString(s: String): Char {
            return s.reduceIndexed { index, acc, c -> if (index % 2 == 0) acc else c }
        }

        fun foldStringWithNamedArgument(s: String): Char {
            return s.reduceIndexed(operation = { index, acc, c -> acc })
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected CharSequence.reduceIndexed to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    func testReduceIndexedOnStringLiteralResolves() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val c: Char = "hello".reduceIndexed { index, acc, ch -> if (index == 0) acc else ch }
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
