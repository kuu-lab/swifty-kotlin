#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeKotlinVersionTests {
    /// `kotlin.KotlinVersion` lives in bundled Kotlin source; the runtime only
    /// injects the targeted Kotlin version as the packed constant consumed by
    /// `KotlinVersion.CURRENT`.
    @Test
    func testCurrentReturnsPackedTargetedKotlinVersion() {
        let packed = __kk_kotlin_version_current()

        #expect(packed / 65536 == 2)
        #expect((packed / 256) % 256 == 3)
        #expect(packed % 256 == 10)
    }
}
#endif
