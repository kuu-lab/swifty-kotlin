#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativePrimitiveByteArraySettersTests {
    private func makeByteArray(length: Int) -> Int {
        kk_array_new(length)
    }

    @Test
    func testPrimitiveByteArrayStoresUseLittleEndianLayout() {
        let array = makeByteArray(length: 14)

        #expect(kk_native_byteArray_setCharAt(array, 0, 0x1234) == 0)
        #expect(kk_native_byteArray_getCharAt(array, 0) == 0x1234)
        #expect(kk_array_get(array, 0, nil) == 0x34)
        #expect(kk_array_get(array, 1, nil) == 0x12)

        #expect(kk_native_byteArray_setFloatAt(array, 2, kk_float_to_bits(Float(1.5))) == 0)
        #expect(kk_native_byteArray_getFloatAt(array, 2) == kk_float_to_bits(Float(1.5)))

        #expect(kk_native_byteArray_setDoubleAt(array, 6, kk_double_to_bits(-2.25)) == 0)
        #expect(kk_native_byteArray_getDoubleAt(array, 6) == kk_double_to_bits(-2.25))
    }
}
#endif
