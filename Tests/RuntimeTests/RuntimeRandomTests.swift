@testable import Runtime
import XCTest

final class RuntimeRandomTests: IsolatedRuntimeXCTestCase {
    // MARK: - nextLong

    func testNextLongReturnsValue() {
        // Just verify it doesn't crash and returns some Int value.
        let result = kk_random_nextLong(0)
        XCTAssertTrue(result >= Int.min && result <= Int.max)
    }

    // MARK: - nextLong(until)

    func testNextLongUntilReturnsWithinRange() {
        var thrown: Int = 0
        let result = kk_random_nextLong_until(0, 100, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= 0 && result < 100)
    }

    func testNextLongUntilThrowsOnNonPositive() {
        var thrown: Int = 0
        _ = kk_random_nextLong_until(0, 0, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=0 should produce an exception")
    }

    func testNextLongUntilThrowsOnNegative() {
        var thrown: Int = 0
        _ = kk_random_nextLong_until(0, -5, &thrown)
        XCTAssertNotEqual(thrown, 0, "until=-5 should produce an exception")
    }

    // MARK: - nextLong(from, until)

    func testNextLongRangeReturnsWithinRange() {
        var thrown: Int = 0
        let result = kk_random_nextLong_range(0, 10, 20, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(result >= 10 && result < 20)
    }

    func testNextLongRangeThrowsOnEmptyRange() {
        var thrown: Int = 0
        _ = kk_random_nextLong_range(0, 10, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "from==until should produce an exception")
    }

    func testNextLongRangeThrowsOnInvertedRange() {
        var thrown: Int = 0
        _ = kk_random_nextLong_range(0, 20, 10, &thrown)
        XCTAssertNotEqual(thrown, 0, "from>until should produce an exception")
    }

    // MARK: - nextFloat

    func testNextFloatReturnsBoxedFloatInUnitRange() {
        let boxed = kk_random_nextFloat(0)
        // The result is a boxed float — unbox it to get float bits.
        let unboxed = kk_unbox_float(boxed)
        let f = floatFromBits(unboxed)
        XCTAssertTrue(f >= 0.0 && f < 1.0, "nextFloat should return a value in [0, 1), got \(f)")
    }

    // MARK: - Helpers

    private func floatFromBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw))
    }
}
