#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNumericModTests {
    @Test
    func testSignedFloorModUsesKotlinRemainderSemantics() {
        #expect(kk_op_floor_mod(-7, 3, nil) == 2)
        #expect(kk_op_floor_mod(7, -3, nil) == -2)
        #expect(kk_op_floor_mod(-7, -3, nil) == -1)
        #expect(kk_op_floor_mod(Int.min, -1, nil) == 0)
    }

    @Test
    func testLongFloorModUsesKotlinRemainderSemantics() {
        #expect(kk_op_lfloor_mod(-7, 3, nil) == 2)
        #expect(kk_op_lfloor_mod(7, -3, nil) == -2)
        #expect(kk_op_lfloor_mod(-7, -3, nil) == -1)
        #expect(kk_op_lfloor_mod(Int.min, -1, nil) == 0)
    }

    // PEC-NUM-0002: `5.mod(0)` throws ArithmeticException("/ by zero").
    @Test
    func testFloorModByZeroThrowsArithmeticException() {
        for floorMod in [kk_op_floor_mod, kk_op_lfloor_mod] {
            var outThrown = 0
            let result = floorMod(5, 0, &outThrown)
            #expect(result == 0)
            #expect(outThrown != 0)
        }
    }

    @Test
    func testFloatingFloorModUsesDivisorSign() {
        #expect(doubleFromBits(kk_op_dfloor_mod(doubleToBits(-7.0), doubleToBits(3.0))) == 2.0)
        #expect(doubleFromBits(kk_op_dfloor_mod(doubleToBits(7.0), doubleToBits(-3.0))) == -2.0)
        #expect(doubleFromBits(kk_op_dfloor_mod(doubleToBits(-7.0), doubleToBits(-3.0))) == -1.0)

        #expect(floatFromBits(kk_op_ffloor_mod(floatToBits(-7.0), floatToBits(3.0))) == 2.0)
        #expect(floatFromBits(kk_op_ffloor_mod(floatToBits(7.0), floatToBits(-3.0))) == -2.0)
        #expect(floatFromBits(kk_op_ffloor_mod(floatToBits(-7.0), floatToBits(-3.0))) == -1.0)
    }

    private func doubleToBits(_ value: Double) -> Int {
        kk_double_to_bits(value)
    }

    private func doubleFromBits(_ raw: Int) -> Double {
        kk_bits_to_double(raw)
    }

    private func floatToBits(_ value: Float) -> Int {
        kk_float_to_bits(value)
    }

    private func floatFromBits(_ raw: Int) -> Float {
        kk_bits_to_float(raw)
    }
}
#endif
