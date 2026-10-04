#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativeByteArrayAccessorsTests {
    private func makeByteArray(_ bytes: [Int]) -> Int {
        let array = kk_array_new(bytes.count)
        for (index, byte) in bytes.enumerated() {
            _ = kk_array_set(array, index, byte, nil)
        }
        return array
    }

    @Test
    func testSignedByteArrayLoadsUseLittleEndianLayout() {
        let array = makeByteArray([0x80, 0xFF, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12])

        #expect(kk_native_byteArray_getByteAt(array, 0) == -128)
        #expect(kk_native_byteArray_getShortAt(array, 0) == -128)
        #expect(kk_native_byteArray_getShortAt(array, 2) == 0x1234)
        #expect(kk_native_byteArray_getIntAt(array, 4) == 0x12345678)
    }

    @Test
    func testSignedLongByteArrayLoad() {
        let positive = makeByteArray([0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
        let negative = makeByteArray([0, 0, 0, 0, 0, 0, 0, 0x80])

        #expect(kk_native_byteArray_getLongAt(positive, 0) == 0x1122334455667788)
        #expect(kk_native_byteArray_getLongAt(negative, 0) == Int.min)
    }
}
#endif
