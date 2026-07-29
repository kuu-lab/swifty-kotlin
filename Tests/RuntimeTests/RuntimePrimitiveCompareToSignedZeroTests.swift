import Foundation
@testable import Runtime
import XCTest

/// BUG-160: `Double`/`Float`.`compareTo` must follow the `Double.compare` /
/// `Float.compare` total order, where `-0.0` sorts before `0.0` (IEEE equality
/// treats them as equal).
final class RuntimePrimitiveCompareToSignedZeroTests: XCTestCase {
    private static let doubleKind: Int32 = 7
    private static let floatKind: Int32 = 6

    private func compareDoubles(_ lhs: Double, _ rhs: Double) -> Int {
        kk_primitive_compareTo(kk_double_to_bits(lhs), kk_double_to_bits(rhs), Self.doubleKind)
    }

    private func compareFloats(_ lhs: Float, _ rhs: Float) -> Int {
        kk_primitive_compareTo(kk_float_to_bits(lhs), kk_float_to_bits(rhs), Self.floatKind)
    }

    func testDoubleSignedZeroTotalOrder() {
        XCTAssertEqual(compareDoubles(-0.0, 0.0), -1)
        XCTAssertEqual(compareDoubles(0.0, -0.0), 1)
        XCTAssertEqual(compareDoubles(0.0, 0.0), 0)
        XCTAssertEqual(compareDoubles(-0.0, -0.0), 0)
    }

    func testFloatSignedZeroTotalOrder() {
        XCTAssertEqual(compareFloats(-0.0, 0.0), -1)
        XCTAssertEqual(compareFloats(0.0, -0.0), 1)
        XCTAssertEqual(compareFloats(0.0, 0.0), 0)
        XCTAssertEqual(compareFloats(-0.0, -0.0), 0)
    }

    func testNonZeroAndNaNOrderingUnchanged() {
        XCTAssertEqual(compareDoubles(-1.0, 0.0), -1)
        XCTAssertEqual(compareDoubles(1.0, -0.0), 1)
        XCTAssertEqual(compareDoubles(1.0, 1.0), 0)
        XCTAssertEqual(compareDoubles(.nan, 0.0), 1)
        XCTAssertEqual(compareDoubles(0.0, .nan), -1)
        XCTAssertEqual(compareDoubles(.nan, .nan), 0)
        XCTAssertEqual(compareDoubles(-.infinity, .infinity), -1)
    }
}
