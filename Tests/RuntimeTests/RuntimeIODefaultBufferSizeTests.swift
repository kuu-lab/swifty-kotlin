#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeIODefaultBufferSizeTests {
    @Test
    func testDefaultBufferSizeMatchesKotlinStdlibValue() {
        #expect(kk_io_default_buffer_size() == 8192)
    }
}
#endif
