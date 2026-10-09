#if canImport(Testing)
import Foundation
import RuntimeABI
import Testing
@testable import Runtime

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeRawBooleanPredicateTests {
    private static let rawBooleanOperations = [
        "_set_contains",
        "_set_is_empty",
        "_mutable_set_add",
        "_mutable_set_remove",
        "_mutable_set_removeAll",
        "_mutable_set_retainAll",
        "_map_is_empty",
    ]

    @Test
    func testSetContainsReturnsRawBoolean() {
        let set = kk_set_of(runtimeTestMakeArray([1, 2, 3]), 3)
        let before = kk_debugging_global_object_count()
        #expect(kk_set_contains(set, 2) == 1)
        #expect(kk_set_contains(set, 9) == 0)
        #expect(kk_set_contains(0, 2) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testSetIsEmptyReturnsRawBoolean() {
        let set = kk_set_of(runtimeTestMakeArray([1]), 1)
        let emptySet = kk_set_of(runtimeTestMakeArray([]), 0)
        let before = kk_debugging_global_object_count()
        #expect(kk_set_is_empty(set) == 0)
        #expect(kk_set_is_empty(emptySet) == 1)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetAddReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(runtimeTestMakeList([1, 2, 3]))
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_add(set, 4, nil) == 1)
        #expect(kk_mutable_set_add(set, 4, nil) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRemoveReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(runtimeTestMakeList([1, 2, 3]))
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_remove(set, 2, nil) == 1)
        #expect(kk_mutable_set_remove(set, 9, nil) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRemoveAllReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(runtimeTestMakeList([1, 2, 3]))
        let present = runtimeTestMakeList([2, 3])
        let absent = runtimeTestMakeList([7, 8])
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_removeAll(set, present, nil) == 1)
        #expect(kk_mutable_set_removeAll(set, absent, nil) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMutableSetRetainAllReturnsRawBoolean() {
        let set = kk_iterable_toMutableSet(runtimeTestMakeList([1, 2, 3]))
        let keepOne = runtimeTestMakeList([1])
        let before = kk_debugging_global_object_count()
        #expect(kk_mutable_set_retainAll(set, keepOne, nil) == 1)
        #expect(kk_mutable_set_retainAll(set, keepOne, nil) == 0)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testMapIsEmptyReturnsRawBoolean() {
        let map = kk_map_of(runtimeTestMakeArray([1, 2]), runtimeTestMakeArray([10, 20]), 2)
        let emptyMap = kk_map_of(0, 0, 0)
        let before = kk_debugging_global_object_count()
        #expect(kk_map_is_empty(map) == 0)
        #expect(kk_map_is_empty(emptyMap) == 1)
        #expect(kk_debugging_global_object_count() == before)
    }

    @Test
    func testRawBooleanCalleeNamesAreDeclaredInSpec() throws {
        let names = RuntimeABISpec.rawBooleanReturnCalleeNames
        for operation in Self.rawBooleanOperations {
            let specs = RuntimeABISpec.collectionFunctions.filter { $0.name.hasSuffix(operation) }
            try #require(specs.count == 1, "Expected one collection ABI declaration for \(operation)")
            let spec = specs[0]
            #expect(names.contains(spec.name), "Missing raw-Boolean callee in spec: \(spec.name)")
            #expect(spec.returnType == .intptr, "\(spec.name) must return intptr_t")
            #expect(spec.returnsRawBoolean)
        }
    }
}
#endif
