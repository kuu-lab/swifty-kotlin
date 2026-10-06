import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeArrayListConstructorTests {
    @Test
    func rejectsNegativeCapacityBeforeAllocation() {
        for capacity in [-1, Int(Int32.min)] {
            var thrown = 0
            #expect(kk_array_list_new_checked(capacity, &thrown) == 0)
            #expect(thrown != 0)
        }
    }

    @Test
    func returnsFreshNominalArrayListsAndClearsThrownSlot() {
        for capacity in [0, 4, Int(Int32.max)] {
            var thrown = 123
            let list = kk_array_list_new_checked(capacity, &thrown)
            #expect(thrown == 0)
            #expect(runtimeObjectTypeID(rawValue: list) == arrayListRuntimeTypeID)
            #expect(kk_list_size(list) == 0)
            #expect(list != kk_array_list_new_checked(capacity, nil))
            _ = kk_mutable_list_add(list, 7, &thrown)
            #expect(thrown == 0)
            #expect(kk_list_size(list) == 1)
        }
    }
}
