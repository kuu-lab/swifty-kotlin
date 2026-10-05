#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNumericFloorDivTests {
    @Test
    func testSignedFloorDivMatchesKotlinSemantics() {
        #expect(kk_op_floor_div(7, 3, nil) == 2)
        #expect(kk_op_floor_div(-7, 3, nil) == -3)
        #expect(kk_op_floor_div(7, -3, nil) == -3)
        #expect(kk_op_floor_div(-7, -3, nil) == 2)
    }

    // PEC-NUM-0002: `5.floorDiv(0)` throws ArithmeticException("/ by zero").
    @Test
    func testFloorDivByZeroThrowsArithmeticException() {
        for floorDiv in [kk_op_floor_div, kk_op_lfloor_div] {
            var outThrown = 0
            let result = floorDiv(1, 0, &outThrown)
            #expect(result == 0)
            #expect(outThrown != 0)
        }
    }

    @Test
    func testLongFloorDivUsesSameRuntimeSemantics() {
        #expect(kk_op_lfloor_div(7, 3, nil) == 2)
        #expect(kk_op_lfloor_div(-7, 3, nil) == -3)
        #expect(kk_op_lfloor_div(7, -3, nil) == -3)
        #expect(kk_op_lfloor_div(-7, -3, nil) == 2)
        #expect(kk_op_lfloor_div(Int.min, -1, nil) == Int.min)
    }
}
#endif
