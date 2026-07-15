#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeSystemTests {
    @Test
    func testProcessStartNanosIsNotInFutureAndStableAcrossCalls() {
        let first = kk_system_process_start_nanos()
        let now = kk_system_nanoTime()
        let second = kk_system_process_start_nanos()

        #expect(first > 0)
        #expect(first <= now, "processStartNanos should not be later than nanoTime.")
        #expect(first == second, "processStartNanos should remain stable across repeated calls.")
    }
}
#endif
