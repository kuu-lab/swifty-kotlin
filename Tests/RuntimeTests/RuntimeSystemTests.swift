#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeSystemTests {
    @Test
    func testProcessStartNanosIsNotInFutureAndStableAcrossCalls() {
        let first = __kk_system_process_start_nanos()
        let now = __kk_system_nanoTime()
        let second = __kk_system_process_start_nanos()

        #expect(first > 0)
        #expect(first <= now, "processStartNanos should not be later than nanoTime.")
        #expect(first == second, "processStartNanos should remain stable across repeated calls.")
    }
}
#endif
