import Testing
@testable import Runtime

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeTestSchedulerABITests {
    @Test
    func clockBridgesUseWordSizedABIWithoutTruncatingLongValues() {
        let advanceTime: (Int, Int) -> Int = kk_test_scheduler_advance_time_by
        let schedulerTime: (Int) -> Int = kk_test_scheduler_current_time
        let scopeTime: (Int) -> Int = kk_test_scope_current_time
        let scope = kk_coroutine_scope_new()
        let scheduler = kk_test_scope_scheduler(scope)

        #expect(schedulerTime(scheduler) == 0)
        #expect(scopeTime(scope) == 0)
        _ = advanceTime(scheduler, 3_000_000_000)
        #expect(schedulerTime(scheduler) == 3_000_000_000)
        #expect(scopeTime(scope) == 3_000_000_000)
    }
}
