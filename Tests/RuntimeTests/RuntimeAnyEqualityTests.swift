#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeAnyEqualityTests {
    private func boolValue(_ raw: Int) -> Bool {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(pointer, to: RuntimeBoolBox.self)
        else {
            return false
        }
        return box.value
    }

    @Test
    func testUnregisteredRuntimeObjectUsesReferenceIdentity() {
        let classID = 0x51_11
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, first, 0)))
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }

    @Test
    func testRegisteredDataClassKeepsStructuralEquality() {
        let classID = 0x51_12
        _ = kk_runtime_register_data_class(classID)
        let first = kk_object_new(1, classID)
        let second = kk_object_new(1, classID)
        _ = kk_array_set(first, 0, 7, nil)
        _ = kk_array_set(second, 0, 7, nil)

        #expect(boolValue(kk_any_equals(first, 0, second, 0)))

        _ = kk_array_set(second, 0, 8, nil)
        #expect(!boolValue(kk_any_equals(first, 0, second, 0)))
    }
}
#endif
