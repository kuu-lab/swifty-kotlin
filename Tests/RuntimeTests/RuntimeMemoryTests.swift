@testable import Runtime
import Testing

/// `systemGCLeavesMetricsQueryable` triggers a real mark-and-sweep
/// (`kk_system_gc`), which reclaims any heap handle not reachable from GC
/// roots. Swift Testing suites share one process and run concurrently, so the
/// GC isolation lock serializes this suite against every other suite that
/// mutates global GC state.
@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeMemoryTests {
    @Test func runtimeGetRuntimeReturnsStableSingletonHandle() {
        #expect(kk_runtime_getRuntime() == kk_runtime_getRuntime())
    }

    @Test func memoryMetricsStayWithinExpectedBounds() {
        let runtimeHandle = kk_runtime_getRuntime()
        #expect(runtimeHandle != 0)

        let total = kk_runtime_totalMemory()
        let free = kk_runtime_freeMemory()
        let max = kk_runtime_maxMemory()

        #expect(total > 0)
        #expect(free >= 0)
        #expect(max >= total)
    }

    @Test func systemGCLeavesMetricsQueryable() {
        kk_system_gc()

        #expect(kk_runtime_totalMemory() > 0)
        #expect(kk_runtime_maxMemory() >= kk_runtime_totalMemory())
    }
}
