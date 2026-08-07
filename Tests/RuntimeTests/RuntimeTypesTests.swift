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

    // MARK: - LazyThreadSafetyMode

    @Test
    func lazyThreadSafetyModeSynchronizedRawValueIsOne() {
        #expect(LazyThreadSafetyMode.synchronized.rawValue == 1)
    }

    @Test
    func lazyThreadSafetyModeNoneRawValueIsZero() {
        #expect(LazyThreadSafetyMode.none.rawValue == 0)
    }

    @Test
    func lazyThreadSafetyModePublicationRawValueIsTwo() {
        #expect(LazyThreadSafetyMode.publication.rawValue == 2)
    }

    @Test
    func lazyThreadSafetyModeInitFromRawValue() {
        #expect(LazyThreadSafetyMode(rawValue: 1) == .synchronized)
        #expect(LazyThreadSafetyMode(rawValue: 0) == LazyThreadSafetyMode.none)
        #expect(LazyThreadSafetyMode(rawValue: 2) == .publication)
    }

    // MARK: - RuntimeObservableBox

    @Test
    func runtimeObservableBoxStoresInitialValue() {
        let box = RuntimeObservableBox(initialValue: 42, callbackFnPtr: 0)
        #expect(box.currentValue == 42)
    }

    @Test
    func runtimeObservableBoxStoresCallbackPointer() {
        let ptr = 12345
        let box = RuntimeObservableBox(initialValue: 0, callbackFnPtr: ptr)
        #expect(box.callbackFnPtr == ptr)
    }

    @Test
    func runtimeObservableBoxCurrentValueIsMutable() {
        let box = RuntimeObservableBox(initialValue: 0, callbackFnPtr: 0)
        box.currentValue = 99
        #expect(box.currentValue == 99)
    }

    // MARK: - RuntimeVetoableBox

    @Test
    func runtimeVetoableBoxStoresInitialValue() {
        let box = RuntimeVetoableBox(initialValue: 7, callbackFnPtr: 0)
        #expect(box.currentValue == 7)
    }

    @Test
    func runtimeVetoableBoxStoresCallbackPointer() {
        let ptr = 67890
        let box = RuntimeVetoableBox(initialValue: 0, callbackFnPtr: ptr)
        #expect(box.callbackFnPtr == ptr)
    }

    @Test
    func runtimeVetoableBoxCurrentValueIsMutable() {
        let box = RuntimeVetoableBox(initialValue: 0, callbackFnPtr: 0)
        box.currentValue = 55
        #expect(box.currentValue == 55)
    }
}
