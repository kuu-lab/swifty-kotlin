#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativeUnsignedByteArrayAccessorsTests {

    @Test
    func testUnsignedByteArrayLoadsUseLittleEndianLayout() {
        let array = makeByteArray([0xFF, 0x80, 0x34, 0x12, 0x21, 0x43, 0x65, 0x87])

        #expect(kk_native_byteArray_getUByteAt(array, 0) == 0xFF)
        #expect(kk_native_byteArray_getUShortAt(array, 1) == 0x3480)
        #expect(kk_native_byteArray_getUIntAt(array, 4) == 0x87654321)
    }

    @Test
    func testUnsignedLongByteArrayLoadPreservesBitPattern() {
        let max = makeByteArray(Array(repeating: 0xFF, count: 8))

        #expect(kk_native_byteArray_getULongAt(max, 0) == -1)
    }
}
#endif
