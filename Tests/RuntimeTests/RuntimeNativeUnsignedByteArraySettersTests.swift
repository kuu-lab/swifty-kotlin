#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativeUnsignedByteArraySettersTests {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    @Test
    func testUnsignedByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 8)

        #expect(kk_native_byteArray_setUByteAt(array, 0, 0xFF) == 0)
        #expect(kk_native_byteArray_getUByteAt(array, 0) == 0xFF)
        #expect(kk_native_byteArray_getByteAt(array, 0) == -1)

        #expect(kk_native_byteArray_setUShortAt(array, 0, 0xABCD) == 0)
        #expect(kk_native_byteArray_getUShortAt(array, 0) == 0xABCD)

        #expect(kk_native_byteArray_setUIntAt(array, 0, 0x87654321) == 0)
        #expect(kk_native_byteArray_getUIntAt(array, 0) == 0x87654321)

        #expect(kk_native_byteArray_setULongAt(array, 0, 0x1122334455667788) == 0)
        #expect(kk_native_byteArray_getULongAt(array, 0) == 0x1122334455667788)
    }

    @Test
    func testUnsignedLongByteArrayStorePreservesBitPattern() {
        let array = makeByteArray(length: 8)

        #expect(kk_native_byteArray_setULongAt(array, 0, -1) == 0)
        #expect(kk_native_byteArray_getULongAt(array, 0) == -1)
    }
}
#endif
