import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcAndMetadata))
struct RuntimeArrayDequeCollectionTests {
    private func makeDeque(_ values: [Int]) -> Int {
        let raw = __kk_arraydeque_new()
        for value in values {
            _ = __kk_arraydeque_addLast(raw, value)
        }
        return raw
    }

    @Test
    func nominalIdentityAndIterableDispatch() throws {
        let raw = makeDeque([1, 2])
        #expect(runtimeObjectTypeID(rawValue: raw) == arrayDequeRuntimeTypeID)
        for name in ["ArrayDeque", "AbstractMutableList", "MutableList", "List", "MutableCollection", "Collection", "Iterable"] {
            let id = runtimeStableNominalTypeID(fqName: "kotlin.collections.\(name)")
            #expect(kk_op_is(raw, Int(6 | (id << 9))) == 1)
        }
        let setID = runtimeStableNominalTypeID(fqName: "kotlin.collections.Set")
        #expect(kk_op_is(raw, Int(6 | (setID << 9))) == 0)
        let iterableID = runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")
        let pointer = kk_itable_lookup_dynamic(raw, Int(iterableID), 0)
        try #require(pointer != 0)
        let iterator = unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let iter = iterator(raw, &thrown)
        #expect(thrown == 0)
        #expect(kk_list_iterator_next(iter, &thrown) == 1)
        #expect(kk_list_iterator_next(iter, &thrown) == 2)
        #expect(thrown == 0)
        #expect(kk_list_iterator_hasNext(iter) == 0)
    }

    @Test
    func listViewsShareRingStorageAndMutationCounter() throws {
        let raw = makeDeque(Array(0..<12))
        for _ in 0..<9 {
            _ = __kk_arraydeque_removeFirst(raw)
        }
        for value in 100..<112 {
            _ = __kk_arraydeque_addLast(raw, value)
        }
        let list = try #require(runtimeListBox(from: raw))
        #expect(list.elements == [9, 10, 11] + Array(100..<112))
        var thrown = 0
        let sub = kk_list_subList(raw, 1, 3, &thrown)
        #expect(thrown == 0)
        #expect(kk_mutable_list_set(sub, 0, 40, &thrown) == 10)
        #expect(__kk_arraydeque_get(raw, 1) == 40)
        _ = kk_mutable_list_add(sub, 50, &thrown)
        #expect(thrown == 0)
        #expect(list.elements == [9, 40, 11, 50] + Array(100..<112))
        #expect(__kk_arraydeque_size(raw) == 16)
        _ = __kk_arraydeque_addFirst(raw, 7)
        #expect(list[0] == 7)
        #expect(list.count == 17)
    }

    @Test
    func iteratorsSeeReplacementsAndDetectDequeStructuralChanges() {
        let raw = makeDeque([1, 2, 3])
        let iter = kk_list_iterator(raw)
        var thrown = 0
        _ = kk_mutable_list_set(raw, 0, 7, &thrown)
        #expect(kk_list_iterator_next(iter, &thrown) == 7)
        #expect(thrown == 0)
        _ = runtimeListIteratorRemove(iter, &thrown)
        #expect(runtimeListBox(from: raw)?.elements == [2, 3])
        #expect(kk_list_iterator_next(iter, &thrown) == 2)
        #expect(thrown == 0)
        _ = __kk_arraydeque_addLast(raw, 4)
        _ = kk_list_iterator_next(iter, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func dequeEqualityHashAndRenderingMatchLists() {
        let raw = makeDeque([1, 2, 3])
        let list = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
        #expect(runtimeValuesEqual(raw, list))
        #expect(runtimeValuesEqual(list, raw))
        #expect(runtimeValueHash(raw) == runtimeValueHash(list))
        #expect(RuntimeElementKey(value: raw) == RuntimeElementKey(value: list))
        #expect(runtimeElementToString(raw) == "[1, 2, 3]")
    }

    @Test
    func subListRejectsReversedRangesWithIllegalArgumentException() throws {
        let raw = makeDeque([1, 2, 3])
        var thrown = 0
        #expect(kk_list_subList(raw, 2, 1, &thrown) == 0)
        let pointer = try #require(UnsafeMutableRawPointer(bitPattern: thrown))
        let exception = try #require(tryCast(pointer, to: RuntimeThrowableBox.self))
        #expect(exception.exceptionFQName == "kotlin.IllegalArgumentException")
    }
}
