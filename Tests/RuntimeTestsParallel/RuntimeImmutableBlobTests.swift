#if canImport(Testing)
import Testing
@testable import Runtime

@Suite
struct RuntimeImmutableBlobTests {
    @Test func factoryTruncatesShortsAndCopiesElements() {
        let shorts = kk_array_new(4)
        _ = kk_array_set(shorts, 0, 65, nil)
        _ = kk_array_set(shorts, 1, 255, nil)
        _ = kk_array_set(shorts, 2, 256, nil)
        _ = kk_array_set(shorts, 3, -1, nil)

        let blob = kk_immutable_blob_of(shorts)
        #expect(blob != shorts)
        #expect(kk_byteArray_size(blob) == 4)
        #expect(kk_native_byteArray_getByteAt(blob, 0) == 65)
        #expect(kk_native_byteArray_getByteAt(blob, 1) == -1)
        #expect(kk_native_byteArray_getByteAt(blob, 2) == 0)
        #expect(kk_native_byteArray_getByteAt(blob, 3) == -1)

        _ = kk_array_set(shorts, 0, 99, nil)
        #expect(kk_native_byteArray_getByteAt(blob, 0) == 65)
    }

    @Test func emptyFactoryReturnsEmptyBlob() {
        let blob = kk_immutable_blob_of(kk_array_new(0))
        #expect(blob != 0)
        #expect(kk_byteArray_size(blob) == 0)
    }
}
#endif
