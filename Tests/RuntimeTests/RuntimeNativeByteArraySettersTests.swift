#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativeByteArraySettersTests {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    @Test
    func testSignedByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 8)

        #expect(kk_native_byteArray_setByteAt(array, 0, -1) == 0)
        #expect(kk_native_byteArray_getByteAt(array, 0) == -1)
        #expect(kk_native_byteArray_getUByteAt(array, 0) == 0xFF)

        #expect(kk_native_byteArray_setShortAt(array, 0, 0x1234) == 0)
        #expect(kk_native_byteArray_getShortAt(array, 0) == 0x1234)
        #expect(kk_array_get(array, 0, nil) == 0x34)
        #expect(kk_array_get(array, 1, nil) == 0x12)

        #expect(kk_native_byteArray_setIntAt(array, 0, 0x12345678) == 0)
        #expect(kk_native_byteArray_getIntAt(array, 0) == 0x12345678)

        #expect(kk_native_byteArray_setLongAt(array, 0, 0x1122334455667788) == 0)
        #expect(kk_native_byteArray_getLongAt(array, 0) == 0x1122334455667788)
    }

    @Test
    func testSignedLongByteArrayStorePreservesBitPattern() {
        let array = makeByteArray(length: 8)

        #expect(kk_native_byteArray_setLongAt(array, 0, Int.min) == 0)
        #expect(kk_native_byteArray_getLongAt(array, 0) == Int.min)
    }
}
#endif
