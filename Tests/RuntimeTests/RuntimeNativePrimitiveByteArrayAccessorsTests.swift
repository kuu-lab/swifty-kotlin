#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativePrimitiveByteArrayAccessorsTests {
    private func makeByteArray(_ bytes: [Int]) -> Int {
        let array = kk_array_new(bytes.count)
        for (index, byte) in bytes.enumerated() {
            _ = kk_array_set(array, index, byte, nil)
        }
        return array
    }

    @Test
    func testPrimitiveByteArrayLoadsUseLittleEndianLayout() {
        let array = makeByteArray([
            0x34, 0x12,
            0x00, 0x00, 0xC0, 0x3F,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xC0,
        ])

        #expect(kk_native_byteArray_getCharAt(array, 0) == 0x1234)
        #expect(kk_native_byteArray_getFloatAt(array, 2) == kk_float_to_bits(Float(1.5)))
        #expect(kk_native_byteArray_getDoubleAt(array, 6) == kk_double_to_bits(-2.25))
    }
}
#endif
