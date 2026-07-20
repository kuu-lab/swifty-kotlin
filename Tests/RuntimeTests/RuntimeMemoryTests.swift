#if canImport(Testing)
@testable import Runtime
import Testing

@Suite
struct RuntimeMemoryTests {
    @Test
    func testRuntimeGetRuntimeReturnsStableSingletonHandle() {
        #expect(kk_runtime_getRuntime() == kk_runtime_getRuntime())
    }

    @Test
    func testMemoryMetricsStayWithinExpectedBounds() {
        let runtimeHandle = kk_runtime_getRuntime()
        #expect(runtimeHandle != 0)

        let total = kk_runtime_totalMemory()
        let free = kk_runtime_freeMemory()
        let max = kk_runtime_maxMemory()

        #expect(total > 0)
        #expect(free >= 0)
        #expect(max >= total)
    }

    @Test
    func testSystemGCLeavesMetricsQueryable() {
        let lease = RuntimeTestIsolationLease(lockSet: .gcOnly)
        defer { lease.release() }
        kk_system_gc()

        #expect(kk_runtime_totalMemory() > 0)
        #expect(kk_runtime_maxMemory() >= kk_runtime_totalMemory())
    }

}
#endif
