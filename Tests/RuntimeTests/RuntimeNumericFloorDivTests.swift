#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNumericFloorDivTests {
    @Test
    func testSignedFloorDivMatchesKotlinSemantics() {
        #expect(kk_op_floor_div(7, 3) == 2)
        #expect(kk_op_floor_div(-7, 3) == -3)
        #expect(kk_op_floor_div(7, -3) == -3)
        #expect(kk_op_floor_div(-7, -3) == 2)
        #expect(kk_op_floor_div(1, 0) == 0)
    }

    @Test
    func testLongFloorDivUsesSameRuntimeSemantics() {
        #expect(kk_op_lfloor_div(7, 3) == 2)
        #expect(kk_op_lfloor_div(-7, 3) == -3)
        #expect(kk_op_lfloor_div(7, -3) == -3)
        #expect(kk_op_lfloor_div(-7, -3) == 2)
        #expect(kk_op_lfloor_div(Int.min, -1) == Int.min)
    }
}
#endif
