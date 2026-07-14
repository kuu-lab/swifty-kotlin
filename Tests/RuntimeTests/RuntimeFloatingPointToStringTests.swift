#if canImport(Testing)
import Foundation
import Testing
@testable import Runtime

/// Documentation-derived conformance tests for Double/Float `toString()`.
///
/// Expected values are taken from Kotlin's documented behaviour (matching
/// java.lang.Double.toString / java.lang.Float.toString), where decimal
/// notation is used for magnitudes in `[1e-3, 1e7)` and scientific notation
/// (`d.dddEexp`) otherwise. These assertions are independent of kotlinc, so
/// they guard the runtime formatter in CI even without the diff harness.
@Suite
struct RuntimeFloatingPointToStringTests {
    @Test
    func testDoubleDecimalRange() {
        #expect(runtimeFormatFloatingPoint(0.0) == "0.0")
        #expect(runtimeFormatFloatingPoint(-0.0) == "-0.0")
        #expect(runtimeFormatFloatingPoint(1.0) == "1.0")
        #expect(runtimeFormatFloatingPoint(-1.0) == "-1.0")
        #expect(runtimeFormatFloatingPoint(100.0) == "100.0")
        #expect(runtimeFormatFloatingPoint(0.5) == "0.5")
        #expect(runtimeFormatFloatingPoint(0.1) == "0.1")
        #expect(runtimeFormatFloatingPoint(0.001) == "0.001")
        #expect(runtimeFormatFloatingPoint(9_999_999.0) == "9999999.0")
        #expect(runtimeFormatFloatingPoint(0.1 + 0.2) == "0.30000000000000004")
    }

    @Test
    func testDoubleScientificRange() {
        // |x| < 1e-3 or >= 1e7 switches to scientific notation.
        #expect(runtimeFormatFloatingPoint(0.0001) == "1.0E-4")
        #expect(runtimeFormatFloatingPoint(1.0e7) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(10_000_000.0) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(123_456_789.0) == "1.23456789E8")
        #expect(runtimeFormatFloatingPoint(1.0e20) == "1.0E20")
        #expect(runtimeFormatFloatingPoint(1.0e-20) == "1.0E-20")
        #expect(runtimeFormatFloatingPoint(Double.greatestFiniteMagnitude) == "1.7976931348623157E308")
    }

    @Test
    func testDoubleSpecialValues() {
        #expect(runtimeFormatFloatingPoint(Double.nan) == "NaN")
        #expect(runtimeFormatFloatingPoint(Double.infinity) == "Infinity")
        #expect(runtimeFormatFloatingPoint(-Double.infinity) == "-Infinity")
    }

    @Test
    func testDoubleMinValue() {
        // SPEC-NUM-0006: Java's FloatingDecimal emits "4.9E-324", not Swift/Ryu's "5.0E-324".
        #expect(runtimeFormatFloatingPoint(Double.leastNonzeroMagnitude) == "4.9E-324")
        #expect(runtimeFormatFloatingPoint(-Double.leastNonzeroMagnitude) == "-4.9E-324")
    }

    @Test
    func testFloatDecimalRange() {
        #expect(runtimeFormatFloatingPoint(Float(0.0)) == "0.0")
        #expect(runtimeFormatFloatingPoint(Float(-0.0)) == "-0.0")
        #expect(runtimeFormatFloatingPoint(Float(1.0)) == "1.0")
        #expect(runtimeFormatFloatingPoint(Float(100.0)) == "100.0")
        #expect(runtimeFormatFloatingPoint(Float(0.1)) == "0.1")
        #expect(runtimeFormatFloatingPoint(Float(0.001)) == "0.001")
        #expect(runtimeFormatFloatingPoint(Float(9_999_999.0)) == "9999999.0")
    }

    @Test
    func testFloatScientificRange() {
        // Float must use the same 1e-3 / 1e7 thresholds as Double; Swift's
        // String(describing:) keeps these in fixed notation, so the formatter
        // is responsible for switching to scientific form.
        #expect(runtimeFormatFloatingPoint(Float(0.0001)) == "1.0E-4")
        #expect(runtimeFormatFloatingPoint(Float(1.0e7)) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(Float(10_000_000.0)) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(Float.greatestFiniteMagnitude) == "3.4028235E38")
    }

    @Test
    func testFloatSpecialValues() {
        #expect(runtimeFormatFloatingPoint(Float.nan) == "NaN")
        #expect(runtimeFormatFloatingPoint(Float.infinity) == "Infinity")
        #expect(runtimeFormatFloatingPoint(-Float.infinity) == "-Infinity")
    }

    @Test
    func testFloatMinValue() {
        // SPEC-NUM-0006: Java's FloatingDecimal emits "1.4E-45", not Swift/Ryu's "1.0E-45".
        #expect(runtimeFormatFloatingPoint(Float.leastNonzeroMagnitude) == "1.4E-45")
        #expect(runtimeFormatFloatingPoint(-Float.leastNonzeroMagnitude) == "-1.4E-45")
    }
}
#endif
