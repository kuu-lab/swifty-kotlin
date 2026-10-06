@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeTypesTests {
    // MARK: - RuntimeStringBox

    @Test
    func runtimeStringBoxStoresValue() {
        let box = RuntimeStringBox("hello")
        #expect(box.value == "hello")
    }

    @Test
    func runtimeStringBoxStoresEmptyString() {
        let box = RuntimeStringBox("")
        #expect(box.value == "")
    }

    @Test
    func runtimeStringBoxStoresUnicodeString() {
        let box = RuntimeStringBox("こんにちは")
        #expect(box.value == "こんにちは")
    }

    // MARK: - RuntimeValue

    @Test
    func runtimeValueRawRoundTripsThroughLegacyRawValue() {
        let value = RuntimeValue(raw: 42)
        #expect(value.tag == RuntimeValue.rawTag)
        #expect(value.legacyRawValue == 42)
    }

    @Test
    func runtimeValueStringPayloadMaterializesLegacyStringBox() throws {
        let bytes = Array("hello".utf8)
        let raw = bytes.withUnsafeBufferPointer { buffer -> Int in
            let data = Int(bitPattern: buffer.baseAddress!)
            let value = RuntimeValue(
                stringData: data,
                length: 5,
                byteCount: bytes.count,
                hash: 0
            )
            return value.legacyRawValue
        }
        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: raw))
        let box = try #require(tryCast(ptr, to: RuntimeStringBox.self))
        #expect(box.value == "hello")
    }

    @Test
    func runtimeValueCharPayloadRoundTripsThroughLegacyRawValue() {
        let value = RuntimeValue(charScalar: 97)
        #expect(value.tag == RuntimeValue.charTag)
        #expect(value.legacyRawValue == 97)
    }

    @Test
    func runtimeValueNullStringComparesAsNullWithoutLegacyBox() {
        let value = RuntimeValue(stringData: 0, length: 0, byteCount: 0, hash: 0)
        let baselineObjectCount = kk_debugging_global_object_count()

        #expect(runtimeCompareValues(value, RuntimeValue(raw: runtimeNullSentinelInt)) == 0)
        #expect(kk_debugging_global_object_count() == baselineObjectCount)
    }

    // MARK: - RuntimeThrowableBox

    @Test
    func runtimeThrowableBoxStoresMessage() {
        let box = RuntimeThrowableBox(message: "Something went wrong")
        #expect(box.message == "Something went wrong")
    }

    @Test
    func runtimeThrowableBoxStoresEmptyMessage() {
        let box = RuntimeThrowableBox(message: "")
        #expect(box.message == "")
    }

    // MARK: - RuntimeArrayBox

    @Test
    func runtimeArrayBoxCreatesZeroFilledArray() {
        let box = RuntimeArrayBox(length: 5)
        #expect(box.elements.count == 5)
        #expect(box.elements.allSatisfy { $0 == 0 })
    }

    @Test
    func runtimeArrayBoxWithZeroLengthCreatesEmptyArray() {
        let box = RuntimeArrayBox(length: 0)
        #expect(box.elements.isEmpty)
    }

    @Test
    func runtimeArrayBoxWithNegativeLengthCreatesEmptyArray() {
        let box = RuntimeArrayBox(length: -10)
        #expect(box.elements.isEmpty)
    }

    @Test
    func runtimeArrayBoxIsMutable() {
        let box = RuntimeArrayBox(length: 3)
        box.elements[1] = 42
        #expect(box.elements[1] == 42)
    }

    @Test
    func runtimeArrayBoxStoresRuntimeValues() {
        let box = RuntimeArrayBox(length: 2)
        box.values[0] = RuntimeValue(raw: 11)
        box.values[1] = RuntimeValue(raw: 22)
        #expect(box.elements == [11, 22])

        box.elements[0] = 33
        #expect(box.values[0].legacyRawValue == 33)
    }

    @Test
    func runtimeListBoxCanViewRuntimeArrayValues() {
        let array = RuntimeArrayBox(length: 2)
        array.values = [RuntimeValue(raw: 7), RuntimeValue(raw: 8)]

        let list = RuntimeListBox(arrayViewOf: array)
        #expect(list.elements == [7, 8])

        list.values[1] = RuntimeValue(raw: 9)
        #expect(array.elements == [7, 9])
    }

    @Test
    func runtimeListBoxSubscriptPreservesAnyFallbackTag() {
        let list = RuntimeListBox(values: [RuntimeValue(raw: 7, anyFallbackTag: 10)])

        list[0] = 9

        #expect(list[0] == 9)
        #expect(list.values[0].anyFallbackTag == 10)
    }

    @Test
    func runtimeListBoxSubscriptMapsThroughViews() {
        let base = RuntimeListBox(values: [
            RuntimeValue(raw: 10, anyFallbackTag: 9),
            RuntimeValue(raw: 20, anyFallbackTag: 10),
        ])
        let reversed = RuntimeListBox(reversedViewOf: base)
        let array = RuntimeArrayBox(length: 2)
        array.values = [
            RuntimeValue(raw: 30, anyFallbackTag: 11),
            RuntimeValue(raw: 40, anyFallbackTag: 12),
        ]
        let arrayView = RuntimeListBox(arrayViewOf: array)

        #expect(reversed.count == 2)
        #expect(reversed[0] == 20)
        reversed[0] = 21
        arrayView[1] = 41

        #expect(base[1] == 21)
        #expect(base.values[1].anyFallbackTag == 10)
        #expect(array[1] == 41)
        #expect(array.values[1].anyFallbackTag == 12)
    }

    @Test
    func runtimeListBoxSubscriptMapsThroughSubList() {
        let base = RuntimeListBox(values: [
            RuntimeValue(raw: 10, anyFallbackTag: 9),
            RuntimeValue(raw: 20, anyFallbackTag: 10),
            RuntimeValue(raw: 30, anyFallbackTag: 11),
            RuntimeValue(raw: 40, anyFallbackTag: 12),
        ])
        let subList = RuntimeListBox(subListOf: base, fromIndex: 1, toIndex: 3)

        #expect(subList.count == 2)
        #expect(subList[0] == 20)
        #expect(subList[1] == 30)

        subList[0] = 21
        subList.setValue(RuntimeValue(raw: 31), at: 1)

        #expect(base.elements == [10, 21, 31, 40])
        #expect(base.values[1].anyFallbackTag == 10)
        #expect(base.values[2].anyFallbackTag == 11)
    }

    @Test
    func runtimeListIteratorSetPreservesAnyFallbackTags() {
        let list = RuntimeListBox(values: [
            RuntimeValue(raw: 1, anyFallbackTag: 9),
            RuntimeValue(raw: 2, anyFallbackTag: 10),
            RuntimeValue(raw: 3, anyFallbackTag: 11),
        ])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iteratorRaw = kk_list_iterator(listRaw)

        while kk_list_iterator_hasNext(iteratorRaw) != 0 {
            _ = kk_list_iterator_next(iteratorRaw)
            _ = runtimeListIteratorSet(iteratorRaw, 99, nil)
        }

        #expect(list.elements == [99, 99, 99])
        #expect(list.values.map(\.anyFallbackTag) == [9, 10, 11])
    }

    @Test
    func runtimeListIteratorSetScalesWithElementCount() {
        let count = 100_000
        let list = RuntimeListBox(values: (0..<count).map {
            RuntimeValue(raw: $0, anyFallbackTag: 10)
        })
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iteratorRaw = kk_list_iterator(listRaw)

        while kk_list_iterator_hasNext(iteratorRaw) != 0 {
            _ = kk_list_iterator_next(iteratorRaw)
            _ = runtimeListIteratorSet(iteratorRaw, 99, nil)
        }

        #expect(list[0] == 99)
        #expect(list[count - 1] == 99)
        #expect(list.values[0].anyFallbackTag == 10)
        #expect(list.values[count - 1].anyFallbackTag == 10)
    }

    // MARK: - modCount / ConcurrentModificationException (Bug A)

    @Test
    func runtimeListBoxModCountBumpsOnlyOnStructuralMutation() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let initial = list.modCount

        list.setValue(RuntimeValue(raw: 99), at: 0)
        #expect(list.modCount == initial, "element replacement must not bump modCount")

        list.withMutableValues { $0.append(RuntimeValue(raw: 4)) }
        #expect(list.modCount == initial + 1, "append must bump modCount")

        list.withMutableValues { $0.remove(at: 0) }
        #expect(list.modCount == initial + 2, "remove must bump modCount")
    }

    @Test
    func runtimeMapBoxModCountBumpsOnNewKeyOnlyNotOnValueUpdate() {
        let map = RuntimeMapBox(keys: [1], values: [100])
        let initial = map.modCount

        map.put(key: 1, value: 200)
        #expect(map.modCount == initial, "updating an existing key must not bump modCount")

        map.put(key: 2, value: 300)
        #expect(map.modCount == initial + 1, "inserting a new key must bump modCount")

        _ = map.remove(key: 1)
        #expect(map.modCount == initial + 2, "removing a key must bump modCount")
    }

    @Test
    func runtimeSetBoxModCountBumpsOnNewElementOnlyNotOnDuplicate() {
        let set = RuntimeSetBox(elements: [1, 2])
        let initial = set.modCount

        #expect(set.insert(rawValue: 1) == false, "duplicate insert must be rejected")
        #expect(set.modCount == initial, "rejected duplicate insert must not bump modCount")

        #expect(set.insert(rawValue: 3) == true)
        #expect(set.modCount == initial + 1, "new element insert must bump modCount")
    }

    @Test
    func kkListIteratorNextThrowsConcurrentModificationExceptionAfterExternalMutation() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)

        #expect(kk_list_iterator_hasNext(iterRaw) != 0)
        var outThrown: Int = 0
        _ = kk_list_iterator_next(iterRaw, &outThrown)
        #expect(outThrown == 0)

        // Mutate the backing list through a handle other than this iterator.
        list.withMutableValues { $0.append(RuntimeValue(raw: 4)) }

        outThrown = 0
        _ = kk_list_iterator_next(iterRaw, &outThrown)
        #expect(outThrown != 0, "next() must throw after an external structural mutation")
        let thrown = tryCast(UnsafeMutableRawPointer(bitPattern: outThrown)!, to: RuntimeConcurrentModificationExceptionBox.self)
        #expect(thrown != nil)
    }

    @Test
    func kkListIteratorOwnRemoveDoesNotTriggerSpuriousComodification() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)
        guard let iter = runtimeListIteratorBox(from: iterRaw) else {
            Issue.record("expected a RuntimeListIteratorBox")
            return
        }

        var outThrown: Int = 0
        _ = kk_list_iterator_next(iterRaw, &outThrown)
        #expect(outThrown == 0)
        #expect(iter.removeLastReturned(), "remove() through the iterator itself must succeed")

        outThrown = 0
        _ = kk_list_iterator_next(iterRaw, &outThrown)
        #expect(outThrown == 0, "an iterator's own remove() must not make its next next() see a comodification")
    }

    @Test
    func kkMapIteratorNextThrowsConcurrentModificationExceptionAfterExternalMutation() {
        let map = RuntimeMapBox(keys: [1, 2], values: [10, 20])
        let mapRaw = registerRuntimeObject(map)
        let iterRaw = kk_map_iterator(mapRaw)

        #expect(kk_map_iterator_hasNext(iterRaw) != 0)
        var outThrown: Int = 0
        _ = kk_map_iterator_next(iterRaw, &outThrown)
        #expect(outThrown == 0)

        map.appendEntry(key: 3, value: 30)

        outThrown = 0
        _ = kk_map_iterator_next(iterRaw, &outThrown)
        #expect(outThrown != 0, "next() must throw after the backing map is structurally mutated elsewhere")
    }

    // MARK: - MutableListIterator/MutableIterator state contract (Bug B)

    @Test
    func runtimeListIteratorRemoveThrowsIllegalStateExceptionBeforeNext() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)

        var outThrown: Int = 0
        _ = runtimeListIteratorRemove(iterRaw, &outThrown)
        #expect(outThrown != 0)
        let thrown = tryCast(UnsafeMutableRawPointer(bitPattern: outThrown)!, to: RuntimeIllegalStateExceptionBox.self)
        #expect(thrown != nil)
    }

    @Test
    func runtimeListIteratorSetThrowsIllegalStateExceptionBeforeNext() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)

        var outThrown: Int = 0
        _ = runtimeListIteratorSet(iterRaw, 9, &outThrown)
        #expect(outThrown != 0)
    }

    @Test
    func runtimeListIteratorRemoveThrowsIllegalStateExceptionRightAfterAdd() {
        let list = RuntimeListBox(elements: [1, 2, 3])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)
        guard let iter = runtimeListIteratorBox(from: iterRaw) else {
            Issue.record("expected a RuntimeListIteratorBox")
            return
        }

        _ = kk_list_iterator_next(iterRaw)
        iter.addBeforeNext(RuntimeValue(raw: 25))

        var outThrown: Int = 0
        _ = runtimeListIteratorRemove(iterRaw, &outThrown)
        #expect(outThrown != 0, "remove() right after add() with no intervening next() must throw")
    }

    @Test
    func runtimeListIteratorRemoveThrowsIllegalStateExceptionOnSecondCall() {
        let list = RuntimeListBox(elements: [1])
        let listRaw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
        let iterRaw = kk_list_iterator(listRaw)

        _ = kk_list_iterator_next(iterRaw)
        var outThrown: Int = 0
        _ = runtimeListIteratorRemove(iterRaw, &outThrown)
        #expect(outThrown == 0)

        outThrown = 0
        _ = runtimeListIteratorRemove(iterRaw, &outThrown)
        #expect(outThrown != 0, "a second remove() with no intervening next() must throw")
    }

    @Test
    func runtimeSetBoxRawValueUsesInsertionOrder() {
        let set = RuntimeSetBox(elements: [10, 20, 30])

        #expect(set.count == 3)
        #expect(set[0] == 10)
        #expect(set[2] == 30)
        #expect(set.rawValue(at: 3) == nil)
    }

    @Test
    func runtimeListBoxReversedViewReflectsBaseMutations() {
        let base = RuntimeListBox(elements: [10, 20, 30])
        let baseRaw = registerRuntimeObject(base, typeID: listRuntimeTypeID)
        let viewRaw = kk_list_as_reversed(baseRaw)
        let view = runtimeListBox(from: viewRaw)

        #expect(view?.elements == [30, 20, 10])

        base.elements[0] = 99
        #expect(view?.elements == [30, 20, 99])

        base.elements.append(40)
        #expect(view?.elements == [40, 30, 20, 99])

        base.elements.remove(at: 1)
        #expect(view?.elements == [40, 30, 99])
    }

    @Test
    func runtimeMapBoxStoresRuntimeValues() {
        let map = RuntimeMapBox(keys: [1], values: [2])
        map.keyValues[0] = RuntimeValue(raw: 10)
        map.entryValues[0] = RuntimeValue(raw: 20)

        #expect(map.keys == [10])
        #expect(map.values == [20])
    }

    // MARK: - RuntimeIntBox

    @Test
    func runtimeIntBoxStoresPositiveValue() {
        let box = RuntimeIntBox(42)
        #expect(box.value == 42)
    }

    @Test
    func runtimeIntBoxStoresNegativeValue() {
        let box = RuntimeIntBox(-100)
        #expect(box.value == -100)
    }

    @Test
    func runtimeIntBoxStoresZero() {
        let box = RuntimeIntBox(0)
        #expect(box.value == 0)
    }

    // MARK: - RuntimeBoolBox

    @Test
    func runtimeBoolBoxStoresTrue() {
        let box = RuntimeBoolBox(true)
        #expect(box.value)
    }

    @Test
    func runtimeBoolBoxStoresFalse() {
        let box = RuntimeBoolBox(false)
        #expect(!box.value)
    }
}
