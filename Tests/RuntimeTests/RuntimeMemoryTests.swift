@testable import Runtime
import XCTest

/// XCTest on purpose: testSystemGCLeavesMetricsQueryable triggers a real
/// mark-and-sweep (kk_system_gc), which reclaims any heap handle not reachable
/// from GC roots. Swift Testing suites share one process and run concurrently,
/// so a GC here would deallocate live handles owned by other suites. XCTest
/// classes run isolated in their own subprocess under `swift test --parallel`.
final class RuntimeMemoryTests: XCTestCase {
    func testRuntimeGetRuntimeReturnsStableSingletonHandle() {
        XCTAssertEqual(kk_runtime_getRuntime(), kk_runtime_getRuntime())
    }

    func testMemoryMetricsStayWithinExpectedBounds() {
        let runtimeHandle = kk_runtime_getRuntime()
        XCTAssertNotEqual(runtimeHandle, 0)

        let total = kk_runtime_totalMemory()
        let free = kk_runtime_freeMemory()
        let max = kk_runtime_maxMemory()

        XCTAssertGreaterThan(total, 0)
        XCTAssertGreaterThanOrEqual(free, 0)
        XCTAssertGreaterThanOrEqual(max, total)
    }

    func testSystemGCLeavesMetricsQueryable() {
        let lease = RuntimeTestIsolationLease(lockSet: .gcOnly)
        defer { lease.release() }
        kk_system_gc()

        XCTAssertGreaterThan(kk_runtime_totalMemory(), 0)
        XCTAssertGreaterThanOrEqual(kk_runtime_maxMemory(), kk_runtime_totalMemory())
    }
}
