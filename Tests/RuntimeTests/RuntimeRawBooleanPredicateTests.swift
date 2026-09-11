#if canImport(Testing)
import Foundation
import RuntimeABI
import Testing
@testable import Runtime

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeRawBooleanPredicateTests {
    private static let rawBooleanCalleeNames: Set<String> = [
        "__kk_set_contains",
        "__kk_set_is_empty",
        "__kk_mutable_set_add",
        "__kk_mutable_set_remove",
        "__kk_mutable_set_removeAll",
        "__kk_mutable_set_retainAll",
        "kk_map_is_empty",
    ]

    @Test
    func testSetContainsReturnsRawBoolean() {
        let set = kk_set_of(makeArray([1, 2, 3]), 3)
        let before = kk_debugging_global_object_count()
        #expect(kk_set_contains(set, 2) == 1)
        #expect(kk_set_contains(set, 9) == 0)
        #expect(kk_set_contains(0, 2) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testSetIsEmptyReturnsRawBoolean() {
        let set = kk_set_of(makeArray([1]), 1)
        let emptySet = kk_set_of(makeArray([]), 0)
        let before = kk_debugging_global_object_count()
        #expect(kk_set_is_empty(set) == 0)
        #expect(kk_set_is_empty(emptySet) == 1)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetAddReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(makeList([1, 2, 3]))
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_add(set, 4, nil) == 1)
        #expect(kk_mutable_set_add(set, 4, nil) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRemoveReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(makeList([1, 2, 3]))
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_remove(set, 2) == 1)
        #expect(kk_mutable_set_remove(set, 9) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRemoveAllReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(makeList([1, 2, 3]))
        let present = makeList([2, 3])
        let absent = makeList([7, 8])
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_removeAll(set, present) == 1)
        #expect(kk_mutable_set_removeAll(set, absent) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRetainAllReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(makeList([1, 2, 3]))
        let keepOne = makeList([1])
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_retainAll(set, keepOne) == 1)
        #expect(kk_mutable_set_retainAll(set, keepOne) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMapIsEmptyReturnsRawBoolean() {
        let map = kk_map_of(makeArray([1, 2]), makeArray([10, 20]), 2)
        let emptyMap = kk_map_of(0, 0, 0)
        let before = kk_debugging_global_object_count()
        #expect(kk_map_is_empty(map) == 0)
        #expect(kk_map_is_empty(emptyMap) == 1)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testRawBooleanCalleeNamesAreDeclaredInSpec() {
        let names = RuntimeABISpec.rawBooleanReturnCalleeNames
        for name in Self.rawBooleanCalleeNames {
            #expect(names.contains(name), "Missing raw-Boolean callee in spec: \(name)")
        }
        for spec in RuntimeABISpec.allFunctions where Self.rawBooleanCalleeNames.contains(spec.name) {
            #expect(spec.returnType == .intptr, "\(spec.name) must return intptr_t")
            #expect(spec.returnsRawBoolean)
        }
    }

    private func makeArray(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
        }
        return arrayRaw
    }

    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = makeArray(elements)
        return kk_list_of(arrayRaw, elements.count)
    }
}
#endif
