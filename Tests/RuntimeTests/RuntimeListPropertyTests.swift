@testable import Runtime
import XCTest

final class RuntimeListPropertyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return kk_list_of(arrayRaw, elements.count)
    }

    func testListIndicesReturnsZeroBasedRange() {
        let indices = kk_list_indices(makeList([10, 20, 30]))

        XCTAssertEqual(kk_range_first(indices), 0)
        XCTAssertEqual(kk_range_last(indices), 2)
        XCTAssertEqual(kk_range_isEmpty(indices), 0)
    }

    func testListIndicesReturnsEmptyRangeForEmptyList() {
        let indices = kk_list_indices(makeList([]))

        XCTAssertEqual(kk_range_first(indices), 0)
        XCTAssertEqual(kk_range_last(indices), -1)
        XCTAssertEqual(kk_range_isEmpty(indices), 1)
    }

    func testListFirstOrNullReturnsHeadOrNullSentinel() {
        XCTAssertEqual(kk_list_firstOrNull(makeList([10, 20])), 10)
        XCTAssertEqual(kk_list_firstOrNull(makeList([])), runtimeNullSentinelInt)
    }

    func testListFirstOrNullPredicateReturnsFirstMatchOrNull() {
        let greaterThanTwo: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, value, _ in
            value > 2 ? 1 : 0
        }
        let fnPtr = unsafeBitCast(greaterThanTwo, to: Int.self)

        var thrown = 0
        XCTAssertEqual(kk_list_firstOrNull_predicate(makeList([1, 2, 3, 4]), fnPtr, 0, &thrown), 3)
        XCTAssertEqual(thrown, 0)

        var thrown2 = 0
        XCTAssertEqual(kk_list_firstOrNull_predicate(makeList([1, 2]), fnPtr, 0, &thrown2), runtimeNullSentinelInt)
        XCTAssertEqual(thrown2, 0)
    }
}
