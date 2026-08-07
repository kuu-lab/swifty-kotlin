import Foundation
@testable import Runtime
import Testing

private let unsignedArrayCopyInitThunk: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { _, index, _ in
    index * 10
}

private func collectionLambdaPointer(_ fn: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int) -> Int {
    Int(bitPattern: unsafeBitCast(fn, to: UnsafeRawPointer.self))
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeUnsignedArrayAsListTests {
    private func makeRuntimeArray(_ elements: [Int]) -> Int {
        let box = RuntimeArrayBox(length: elements.count)
        box.elements = elements
        return registerRuntimeObject(box)
    }

    private func arrayElements(from raw: Int) -> [Int] {
        runtimeArrayBox(from: raw)?.elements ?? []
    }

    private func listElements(from raw: Int) -> [Int] {
        runtimeListBox(from: raw)?.elements ?? []
    }

    @Test func unsignedPrimitiveArraySignedViewsShareBackingStorage() {
        let ubyteRaw = makeRuntimeArray([1, 2])
        let byteRaw = kk_uByteArray_asByteArray(ubyteRaw)
        #expect(byteRaw == ubyteRaw)
        runtimeArrayBox(from: byteRaw)?.elements[1] = 127
        #expect(arrayElements(from: ubyteRaw) == [1, 127])

        let ushortRaw = makeRuntimeArray([10, 20])
        let shortRaw = kk_uShortArray_asShortArray(ushortRaw)
        #expect(shortRaw == ushortRaw)
        runtimeArrayBox(from: shortRaw)?.elements[0] = 32_767
        #expect(arrayElements(from: ushortRaw) == [32_767, 20])

        let uintRaw = makeRuntimeArray([100, 200])
        let intRaw = kk_uIntArray_asIntArray(uintRaw)
        #expect(intRaw == uintRaw)
        runtimeArrayBox(from: intRaw)?.elements[1] = 900
        #expect(arrayElements(from: uintRaw) == [100, 900])

        let ulongRaw = makeRuntimeArray([1000, 2000])
        let longRaw = kk_uLongArray_asLongArray(ulongRaw)
        #expect(longRaw == ulongRaw)
        runtimeArrayBox(from: longRaw)?.elements[0] = 9_000
        #expect(arrayElements(from: ulongRaw) == [9_000, 2000])
    }

    @Test func signedPrimitiveArrayUnsignedViewConversionsReturnSameArray() {
        let byteRaw = makeRuntimeArray([1, 2, 3])
        let ubyteRaw = kk_byteArray_asUByteArray(byteRaw)
        #expect(ubyteRaw == byteRaw)
        runtimeArrayBox(from: byteRaw)?.elements[1] = 9
        #expect(arrayElements(from: ubyteRaw) == [1, 9, 3])

        let shortRaw = makeRuntimeArray([10, 20, 30])
        let ushortRaw = kk_shortArray_asUShortArray(shortRaw)
        #expect(ushortRaw == shortRaw)

        let intRaw = makeRuntimeArray([100, 200])
        let uintRaw = kk_intArray_asUIntArray(intRaw)
        #expect(uintRaw == intRaw)

        let longRaw = makeRuntimeArray([1000, 2000])
        let ulongRaw = kk_longArray_asULongArray(longRaw)
        #expect(ulongRaw == longRaw)
    }

    @Test func uByteArrayAsListViewReflectsMutations() throws {
        let arrayRaw = makeRuntimeArray([1, 2, 3])
        let listRaw = kk_uByteArray_asList(arrayRaw)

        #expect(listElements(from: listRaw) == [1, 2, 3])

        let arrayBox = try #require(runtimeArrayBox(from: arrayRaw), "Expected a runtime array box.")
        arrayBox.elements[1] = 9

        #expect(listElements(from: listRaw) == [1, 9, 3])
    }

    @Test func uShortArrayAsListViewReflectsMutations() throws {
        let arrayRaw = makeRuntimeArray([10, 20, 30])
        let listRaw = kk_uShortArray_asList(arrayRaw)

        #expect(listElements(from: listRaw) == [10, 20, 30])

        let arrayBox = try #require(runtimeArrayBox(from: arrayRaw), "Expected a runtime array box.")
        arrayBox.elements[1] = 90

        #expect(listElements(from: listRaw) == [10, 90, 30])
    }

    @Test func uLongArrayAsListViewReflectsMutations() throws {
        let arrayRaw = makeRuntimeArray([1000, 2000, 3000])
        let listRaw = kk_uLongArray_asList(arrayRaw)

        #expect(listElements(from: listRaw) == [1000, 2000, 3000])

        let arrayBox = try #require(runtimeArrayBox(from: arrayRaw), "Expected a runtime array box.")
        arrayBox.elements[1] = 9000

        #expect(listElements(from: listRaw) == [1000, 9000, 3000])
    }

    @Test func unsignedPrimitiveArrayToTypedArrayCopiesElements() {
        let ubyteRaw = makeRuntimeArray([1, 2, 3])
        let ubyteCopy = kk_array_copyOf(ubyteRaw)
        #expect(ubyteCopy != ubyteRaw)
        #expect(arrayElements(from: ubyteCopy) == [1, 2, 3])

        let ushortRaw = makeRuntimeArray([10, 20, 30])
        let ushortCopy = kk_array_copyOf(ushortRaw)
        #expect(ushortCopy != ushortRaw)
        #expect(arrayElements(from: ushortCopy) == [10, 20, 30])

        let uintRaw = makeRuntimeArray([100, 200])
        let uintCopy = kk_array_copyOf(uintRaw)
        runtimeArrayBox(from: uintCopy)?.elements[1] = 900
        #expect(arrayElements(from: uintRaw) == [100, 200])
        #expect(arrayElements(from: uintCopy) == [100, 900])

        let ulongRaw = makeRuntimeArray([1000, 2000])
        let ulongCopy = kk_array_copyOf(ulongRaw)
        runtimeArrayBox(from: ulongCopy)?.elements[0] = 9000
        #expect(arrayElements(from: ulongRaw) == [1000, 2000])
        #expect(arrayElements(from: ulongCopy) == [9000, 2000])
    }

    @Test func unsignedPrimitiveArrayCopyOfNewSizeFillsZerosAndCopiesElements() throws {
        let arrayRaw = makeRuntimeArray([5, 6, 7])

        let grownRaw = kk_array_copyOf_newSize(arrayRaw, 5)
        #expect(arrayElements(from: grownRaw) == [5, 6, 7, 0, 0])

        let shrunkRaw = kk_array_copyOf_newSize(arrayRaw, 2)
        #expect(arrayElements(from: shrunkRaw) == [5, 6])

        let grownBox = try #require(runtimeArrayBox(from: grownRaw), "Expected a runtime array box.")
        grownBox.elements[0] = 99
        #expect(arrayElements(from: arrayRaw) == [5, 6, 7])
    }

    @Test func unsignedPrimitiveArrayCopyOfNewSizeInitFillsAddedElements() {
        let arrayRaw = makeRuntimeArray([7, 8])
        let fnPtr = collectionLambdaPointer(unsignedArrayCopyInitThunk)

        let grownRaw = kk_array_copyOf_newSize_init(arrayRaw, 5, fnPtr, 0, nil)
        #expect(arrayElements(from: grownRaw) == [7, 8, 20, 30, 40])

        let shrunkRaw = kk_array_copyOf_newSize_init(arrayRaw, 1, fnPtr, 0, nil)
        #expect(arrayElements(from: shrunkRaw) == [7])
    }

    @Test func unsignedPrimitiveArrayCopyOfRangeCopiesElements() {
        let ubyteRaw = makeRuntimeArray([1, 2, 3])
        let ubyteCopy = kk_array_copyOfRange(ubyteRaw, 1, 3, nil)
        #expect(ubyteCopy != ubyteRaw)
        #expect(arrayElements(from: ubyteCopy) == [2, 3])

        let ushortRaw = makeRuntimeArray([10, 20, 30])
        let ushortCopy = kk_array_copyOfRange(ushortRaw, 0, 2, nil)
        #expect(ushortCopy != ushortRaw)
        #expect(arrayElements(from: ushortCopy) == [10, 20])

        let uintRaw = makeRuntimeArray([100, 200, 300])
        let uintCopy = kk_array_copyOfRange(uintRaw, 1, 3, nil)
        runtimeArrayBox(from: uintCopy)?.elements[0] = 900
        #expect(arrayElements(from: uintRaw) == [100, 200, 300])
        #expect(arrayElements(from: uintCopy) == [900, 300])

        let ulongRaw = makeRuntimeArray([1000, 2000, 3000])
        let ulongCopy = kk_array_copyOfRange(ulongRaw, 0, 2, nil)
        runtimeArrayBox(from: ulongCopy)?.elements[1] = 9000
        #expect(arrayElements(from: ulongRaw) == [1000, 2000, 3000])
        #expect(arrayElements(from: ulongCopy) == [1000, 9000])
    }
}
