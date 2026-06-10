@testable import CompilerCore
import XCTest

final class ComparisonsMinOfComparable2FunctionTests: XCTestCase {
    func testMinOfComparable2ArgFunctionResolvesInSource() throws {
        // Use String (a Kotlin built-in Comparable) so that the subtype
        // check primitive <: Comparable<primitive> is satisfied without
        // relying on user-defined generic supertype resolution.
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.minOf

        fun pickEarliest(a: String, b: String): String {
            return minOf(a, b)
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected minOf(a, b) Comparable 2-arg overload to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
