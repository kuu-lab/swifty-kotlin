@testable import CompilerCore
import XCTest

final class ComparisonsMaxOfComparable2FunctionTests: XCTestCase {
    func testMaxOfComparable2ArgFunctionResolvesInSource() throws {
        // Use String (a Kotlin built-in Comparable) so that the subtype
        // check primitive <: Comparable<primitive> is satisfied without
        // relying on user-defined generic supertype resolution.
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.maxOf

        fun pickLatest(a: String, b: String): String {
            return maxOf(a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected maxOf(a, b) Comparable 2-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
