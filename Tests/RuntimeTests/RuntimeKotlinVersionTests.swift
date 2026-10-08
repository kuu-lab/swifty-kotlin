#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeKotlinVersionTests {
    @Test
    func testCurrentBridgeReturnsPackedTargetVersion() {
        let packed = __kk_kotlin_version_current()

        #expect((packed >> 16) & 0xFF == 2)
        #expect((packed >> 8) & 0xFF == 3)
        #expect(packed & 0xFF == 10)
    }
}
#endif
