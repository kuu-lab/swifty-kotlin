@testable import CompilerCore
import XCTest

/// STDLIB-COMP-FN-028: Validates that `maxWithOrNull(comparator)` resolves through
/// Sema for the receivers wired through the standard aggregate / HOF
/// infrastructure — `List<T>` and `Sequence<T>`. The companion runtime entry
/// points are `kk_list_maxWithOrNull` and `kk_sequence_maxWithOrNull`.
final class ComparisonsMaxWithOrNullFunctionTests: XCTestCase {
    func testMaxWithOrNullFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.comparisons.naturalOrder

        fun largestList(xs: List<Int>): Int? {
            return xs.maxWithOrNull(naturalOrder<Int>())
        }

        fun largestSequence(xs: Sequence<Int>): Int? {
            return xs.maxWithOrNull(naturalOrder<Int>())
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected maxWithOrNull to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
