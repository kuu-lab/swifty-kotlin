#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimePlatformTests {

    // MARK: - kk_platform_memoryModel

    @Test
    func testMemoryModelRuntimeEntryPointIsAvailable() {
        // STDLIB-NATIVE-PLATFORM-ABI-001: kk_platform_memoryModel is now implemented.
        #expect((kk_platform_memoryModel(0) as Int?) != nil)
    }

    @Test
    func testMemoryModelReturnsBoxedInt() {
        let result = kk_platform_memoryModel(0)
        // A valid boxed Int is non-zero (the boxing scheme never returns 0 for a tagged pointer).
        #expect(result != 0)
    }

    @Test
    func testMemoryModelOrdinalIsValidRange() {
        let result = kk_platform_memoryModel(0)
        let unboxed = kk_unbox_int(result)
        // MemoryModel ordinals: STRICT=0, RELAXED=1, EXPERIMENTAL=2
        #expect(unboxed >= 0)
        #expect(unboxed <= 2)
    }

    @Test
    func testMemoryModelDefaultIsExperimental() {
        // Without KSWIFTK_MEMORY_MODEL_STRICT / _RELAXED build flags the default is EXPERIMENTAL (2).
        let result = kk_platform_memoryModel(0)
        let unboxed = kk_unbox_int(result)
        #expect(unboxed == 2, "Default memory model should be EXPERIMENTAL (ordinal 2)")
    }

    @Test
    func testMemoryModelIsStableAcrossCalls() {
        #expect(kk_platform_memoryModel(0) == kk_platform_memoryModel(0))
    }

    @Test
    func testMemoryModelIgnoresPlatformRawArgument() {
        #expect(kk_platform_memoryModel(0) == kk_platform_memoryModel(42))
    }

    // MARK: - kk_platform_isDebugBinary

    @Test
    func testIsDebugBinaryReturnsZeroOrOne() {
        let result = kk_platform_isDebugBinary(0)
        #expect(result == 0 || result == 1)
    }

    @Test
    func testIsDebugBinaryIsTrueInDebugBuilds() {
        // Tests run under the debug configuration; _isDebugAssertConfiguration() should be true.
        let result = kk_platform_isDebugBinary(0)
        #expect(result == 1, "kk_platform_isDebugBinary should return 1 when compiled with debug assertions")
    }

    @Test
    func testIsDebugBinaryIsStableAcrossCalls() {
        #expect(kk_platform_isDebugBinary(0) == kk_platform_isDebugBinary(0))
    }

    @Test
    func testIsDebugBinaryIgnoresPlatformRawArgument() {
        #expect(kk_platform_isDebugBinary(0) == kk_platform_isDebugBinary(99))
    }
}
#endif
