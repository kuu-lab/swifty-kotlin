import Foundation
@testable import Runtime
import Testing

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
        let ubyteCopy = __kk_array_copyOf(ubyteRaw)
        #expect(ubyteCopy != ubyteRaw)
        #expect(arrayElements(from: ubyteCopy) == [1, 2, 3])

        let ushortRaw = makeRuntimeArray([10, 20, 30])
        let ushortCopy = __kk_array_copyOf(ushortRaw)
        #expect(ushortCopy != ushortRaw)
        #expect(arrayElements(from: ushortCopy) == [10, 20, 30])

        let uintRaw = makeRuntimeArray([100, 200])
        let uintCopy = __kk_array_copyOf(uintRaw)
        runtimeArrayBox(from: uintCopy)?.elements[1] = 900
        #expect(arrayElements(from: uintRaw) == [100, 200])
        #expect(arrayElements(from: uintCopy) == [100, 900])

        let ulongRaw = makeRuntimeArray([1000, 2000])
        let ulongCopy = __kk_array_copyOf(ulongRaw)
        runtimeArrayBox(from: ulongCopy)?.elements[0] = 9000
        #expect(arrayElements(from: ulongRaw) == [1000, 2000])
        #expect(arrayElements(from: ulongCopy) == [9000, 2000])
    }

}
