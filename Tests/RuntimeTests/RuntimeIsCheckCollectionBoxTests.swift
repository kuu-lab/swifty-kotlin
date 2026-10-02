import Foundation
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcAndMetadata))
struct RuntimeIsCheckCollectionBoxTests {
    private func token(_ name: String) -> Int {
        let typeID = runtimeStableNominalTypeID(fqName: name)
        return Int(6 | (typeID << 9))
    }

    private func iteratorMethod(_ raw: Int, slot: Int) throws -> @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int {
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterator")), slot)
        try #require(pointer != 0)
        return unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
    }

    @Test
    func erasedIteratorBoxesHaveIdentityAndCallableTables() throws {
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]))
        let boxes: [AnyObject] = [
            RuntimeListIteratorBox(elements: [7]),
            RuntimeMapIteratorBox(mapRaw: map, keys: [1], values: [2]),
            RuntimeMutableMapIteratorBox(mapRaw: map, keys: [1]),
            RuntimeSequenceIteratorBox(seq: RuntimeSequenceBox(steps: [.source(elements: [7])])),
            RuntimeIndexingIteratorBox(values: [runtimeValueFromCollectionABI(7)]),
            RuntimeRangeIteratorBox(current: 7, last: 7, step: 1, kind: .intRange),
        ]
        for box in boxes {
            let raw = registerRuntimeObject(box)
            #expect(runtimeObjectTypeID(rawValue: raw) != nil)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 0)
            #expect(kk_op_is(raw, token("kotlin.collections.List")) == 0)
            #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
            var thrown = 0
            let hasNext = try iteratorMethod(raw, slot: 0)
            let next = try iteratorMethod(raw, slot: 1)
            #expect(hasNext(raw, &thrown) == 1)
            #expect(thrown == 0)
            _ = next(raw, &thrown)
            #expect(thrown == 0)
            #expect(hasNext(raw, &thrown) == 0)
            _ = next(raw, &thrown)
            #expect(thrown != 0)
        }
    }

    @Test
    func factoryIteratorCastsUseRegisteredIdentity() {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1, 2, 3]))
        let raw = kk_list_iterator(list)
        let iteratorToken = token("kotlin.collections.Iterator")
        #expect(kk_op_is(raw, iteratorToken) == 1)
        #expect(kk_op_safe_cast(raw, iteratorToken) == raw)
        var thrown = 0
        #expect(kk_op_cast(raw, iteratorToken, &thrown) == raw)
        #expect(thrown == 0)
        let listToken = token("kotlin.collections.List")
        #expect(kk_op_safe_cast(raw, listToken) == runtimeNullSentinelInt)
        _ = kk_op_cast(raw, listToken, &thrown)
        #expect(thrown != 0)
        #expect(kk_op_is(thrown, token("kotlin.ClassCastException")) == 1)
    }

    @Test
    func mutableIdentityIncludesIteratorAndRemoveDispatch() throws {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1, 2]))
        let raw = kk_list_iterator(list)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        var thrown = 0
        #expect(kk_iterator_next(raw, &thrown) == 1)
        let removePointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.MutableIterator")), 0)
        try #require(removePointer != 0)
        let remove = unsafeBitCast(removePointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        _ = remove(raw, &thrown)
        #expect(thrown == 0)
        #expect(runtimeListBox(from: list)?.elements == [2])
        let readonly = registerRuntimeObject(RuntimeListIteratorBox(elements: [1]))
        #expect(kk_op_is(readonly, token("kotlin.collections.MutableIterator")) == 0)
    }

    @Test
    func erasedSequenceHasIdentityAndIteratorDispatch() throws {
        let box: AnyObject = RuntimeSequenceBox(steps: [.source(elements: [4])])
        let raw = registerRuntimeObject(box)
        #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 0)
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.sequences.Sequence")), 0)
        try #require(pointer != 0)
        let iterator = unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let iter = iterator(raw, &thrown)
        #expect(thrown == 0)
        #expect(kk_op_is(iter, token("kotlin.collections.Iterator")) == 1)
        #expect(try iteratorMethod(iter, slot: 1)(iter, &thrown) == 4)
    }

    @Test
    func indexingIterableHasIdentityAndIteratorDispatch() throws {
        let list = registerRuntimeObject(RuntimeListBox(elements: [9]))
        let raw = registerRuntimeObject(RuntimeIndexingIterableBox(listRaw: list) as AnyObject)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterable")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.Collection")) == 0)
        let pointer = kk_itable_lookup_dynamic(raw, Int(runtimeStableNominalTypeID(fqName: "kotlin.collections.Iterable")), 0)
        try #require(pointer != 0)
        let iterator = unsafeBitCast(pointer, to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self)
        var thrown = 0
        let iter = iterator(raw, &thrown)
        #expect(kk_op_is(iter, token("kotlin.collections.Iterator")) == 1)
        #expect(try iteratorMethod(iter, slot: 0)(iter, &thrown) == 1)
        let value = try iteratorMethod(iter, slot: 1)(iter, &thrown)
        #expect((resolveRuntimeObjectHandle(value) as? RuntimePairBox)?.first == 0)
        #expect(thrown == 0)
    }

    @Test
    func compatibilitySequenceTableDoesNotChangeListIdentity() {
        let raw = registerRuntimeObject(RuntimeListBox(elements: [1]))
        #expect(kk_op_is(raw, token("kotlin.collections.List")) == 1)
        #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
    }

    @Test
    func erasedCollectionBoxesKeepCollectionIdentity() {
        let list = registerRuntimeObject(RuntimeListBox(elements: [1]) as AnyObject)
        let set = registerRuntimeObject(RuntimeSetBox(elements: [1]) as AnyObject)
        let map = registerRuntimeObject(RuntimeMapBox(keys: [1], values: [2]) as AnyObject)
        #expect(kk_op_is(list, token("kotlin.collections.List")) == 1)
        #expect(kk_op_is(set, token("kotlin.collections.Set")) == 1)
        #expect(kk_op_is(map, token("kotlin.collections.Map")) == 1)
        for raw in [list, set, map] {
            #expect(kk_op_is(raw, token("kotlin.sequences.Sequence")) == 0)
            #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 0)
        }
        #expect(kk_op_is(map, token("kotlin.collections.Iterable")) == 0)
    }

    @Test
    func iteratorBuilderHasIdentityAndIteratorDispatch() throws {
        let thunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { builderRaw, _ in
            _ = __kk_iterator_builder_yield(builderRaw, 8)
            return 0
        }
        let raw = __kk_iterator_builder_build(unsafeBitCast(thunk, to: Int.self))
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 0)
        var thrown = 0
        let hasNext = try iteratorMethod(raw, slot: 0)
        #expect(hasNext(raw, &thrown) == 1)
        #expect(try iteratorMethod(raw, slot: 1)(raw, &thrown) == 8)
        #expect(hasNext(raw, &thrown) == 0)
        #expect(thrown == 0)
    }

    @Test
    func bufferedLineIteratorHasIdentityAndIteratorDispatch() throws {
        let reader = RuntimeBufferedReaderBox(data: Data("line\n".utf8))
        let raw = registerRuntimeObject(RuntimeBufferedLineIteratorBox(reader: reader) as AnyObject)
        #expect(kk_op_is(raw, token("kotlin.collections.Iterator")) == 1)
        #expect(kk_op_is(raw, token("kotlin.collections.MutableIterator")) == 0)
        var thrown = 0
        let hasNext = try iteratorMethod(raw, slot: 0)
        let next = try iteratorMethod(raw, slot: 1)
        #expect(hasNext(raw, &thrown) == 1)
        #expect(runtimeStringFromRaw(next(raw, &thrown)) == "line")
        #expect(hasNext(raw, &thrown) == 0)
        _ = next(raw, &thrown)
        #expect(thrown != 0)
    }
}
