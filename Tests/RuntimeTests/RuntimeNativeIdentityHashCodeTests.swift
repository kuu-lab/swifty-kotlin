#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeNativeIdentityHashCodeTests {
    @Test
    func testIdentityHashCodeIsStableForRuntimeObject() {
        let objectRaw = kk_array_new(0)
        let first = kk_native_identityHashCode(objectRaw)
        let second = kk_native_identityHashCode(objectRaw)

        #expect(first != 0)
        #expect(first == second)
    }

    @Test
    func testIdentityHashCodeReturnsZeroForNull() {
        #expect(kk_native_identityHashCode(0) == 0)
        #expect(kk_native_identityHashCode(runtimeNullSentinelInt) == 0)
    }
}
#endif
