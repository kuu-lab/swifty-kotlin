#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeListBoundsTests {
    private func makeList(_ elements: [Int]) -> Int {
        let arrayRaw = kk_array_new(elements.count)
        var thrown = 0
        for (index, element) in elements.enumerated() {
            _ = kk_array_set(arrayRaw, index, element, &thrown)
            #expect(thrown == 0)
        }
        return kk_list_of(arrayRaw, elements.count)
    }

    private func requireThrownBox(_ thrown: Int) throws -> RuntimeThrowableBox {
        let ptr = try #require(
            UnsafeMutableRawPointer(bitPattern: thrown),
            "thrown channel value is not a valid pointer"
        )
        return try #require(
            tryCast(ptr, to: RuntimeThrowableBox.self),
            "thrown value must be a RuntimeThrowableBox"
        )
    }

    @Test
    func listGetOutOfBoundsSetsIndexException() throws {
        let list = makeList([1])
        var thrown = 0

        #expect(kk_list_get(list, 5, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.IndexOutOfBoundsException")
    }

    @Test
    func mutableListRemoveAtOutOfBoundsSetsIndexException() throws {
        let list = makeList([1, 2])
        var thrown = 0

        #expect(kk_mutable_list_removeAt(list, 9, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.IndexOutOfBoundsException")
    }

    @Test
    func listIteratorNextPastEndSetsNoSuchElementException() throws {
        let iterator = kk_list_iterator(makeList([1]))
        #expect(kk_list_iterator_next(iterator) == 1)

        var thrown = 0
        #expect(kk_list_iterator_next(iterator, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NoSuchElementException")
    }

    @Test
    func genericIteratorNextPastEndSetsNoSuchElementException() throws {
        let iterator = kk_list_iterator(makeList([1]))
        var thrown = 0
        #expect(kk_iterator_next(iterator, &thrown) == 1)
        #expect(thrown == 0)

        #expect(kk_iterator_next(iterator, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NoSuchElementException")
    }

    @Test
    func rangeIteratorNextPastEndSetsNoSuchElementException() throws {
        let iterator = kk_range_iterator(kk_op_rangeTo(7, 7), nil)
        var thrown = 0
        #expect(kk_iterator_next(iterator, &thrown) == 7)
        #expect(thrown == 0)

        #expect(kk_iterator_next(iterator, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NoSuchElementException")
    }

    @Test
    func rangeIteratorNextZeroElementThenPastEndThrows() throws {
        let iterator = kk_range_iterator(kk_op_rangeTo(0, 0), nil)
        var thrown = 0
        #expect(kk_iterator_next(iterator, &thrown) == 0)
        #expect(thrown == 0)

        #expect(kk_iterator_next(iterator, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NoSuchElementException")
    }

    @Test
    func mapIteratorNextPastEndSetsNoSuchElementException() throws {
        let keys = kk_array_new(1)
        let values = kk_array_new(1)
        var thrown = 0
        _ = kk_array_set(keys, 0, 11, &thrown)
        #expect(thrown == 0)
        _ = kk_array_set(values, 0, 22, &thrown)
        #expect(thrown == 0)
        let iterator = kk_map_iterator(kk_map_of(keys, values, 1))
        #expect(kk_map_iterator_next(iterator, &thrown) == 11)
        #expect(thrown == 0)

        #expect(kk_map_iterator_next(iterator, &thrown) == 0)
        let box = try requireThrownBox(thrown)
        #expect(box.exceptionFQName == "kotlin.NoSuchElementException")
    }
}
#endif
