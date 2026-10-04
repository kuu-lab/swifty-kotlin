#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeUnitBoxingTests {
    private func boolValue(_ raw: Int) -> Bool {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(pointer, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    @Test
    func unitBoxMaintainsSingletonIdentityAcrossErasureAndGCReset() {
        let first = kk_box_unit(0)
        let second = kk_box_unit(0)

        #expect(first != 0)
        #expect(first == second)
        #expect(kk_box_unit(first) == first)
        #expect(runtimeIsUnitValue(first))
        #expect(runtimeIsUnitBox(first))
        #expect(kk_op_eq(first, second) == 1)
        #expect(kk_op_ne(first, second) == 0)
        #expect(boolValue(kk_any_equals(first, 1, second, 1)))
        #expect(extractString(from: kk_any_to_string(first, 1)) == "kotlin.Unit")

        kk_runtime_reset_gc()

        #expect(kk_box_unit(0) == first)
        #expect(runtimeIsUnitBox(first))
    }
}
#endif
