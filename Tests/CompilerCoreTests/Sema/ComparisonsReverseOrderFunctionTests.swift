@testable import CompilerCore
import XCTest

final class ComparisonsReverseOrderFunctionTests: XCTestCase {
    func testReverseOrderFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.reverseOrder

        fun makeComparator(): Comparator<Int> {
            return reverseOrder<Int>()
        }
        """)
        try runSema(ctx)
        XCTAssertFalse(ctx.diagnostics.hasError, "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
