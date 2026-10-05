import Foundation
@testable import Runtime
import Testing

private final class JobStartCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeJobStartTests {
    @Test
    func lazyJobPublishesActiveStateAndStartsOnce() {
        let job = RuntimeJobHandle()
        let handle = runtimeRegisterObject(job)
        let calls = JobStartCounter()
        job.installLazyStartBody {
            #expect(job.isActiveSnapshot())
            calls.increment()
        }
        #expect(kk_job_is_active(handle) == 0)
        #expect(kk_job_start(handle) == 1)
        #expect(kk_job_is_active(handle) == 1)
        #expect(kk_job_start(handle) == 0)
        #expect(calls.count == 1)
        job.markStarted()
        #expect(job.complete(with: 42))
        #expect(kk_job_start(handle) == 0)
    }

    @Test
    func lazyDeferredPublishesActiveStateBeforeDispatch() {
        let task = RuntimeAsyncTask()
        let handle = runtimeRegisterObject(task)
        let calls = JobStartCounter()
        task.installLazyStartBody {
            #expect(task.isActiveSnapshot())
            #expect(task.completionJob.isActiveSnapshot())
            calls.increment()
        }
        #expect(kk_job_is_active(handle) == 0)
        #expect(kk_job_start(handle) == 1)
        #expect(kk_job_is_active(handle) == 1)
        #expect(kk_job_start(handle) == 0)
        #expect(calls.count == 1)
        task.markStarted()
        task.complete(with: 42)
        #expect(kk_job_start(handle) == 0)
        #expect(kk_kxmini_async_await(handle, 0) == 42)
    }

    @Test(arguments: [false, true])
    func cancelledLazyHandlesNeverStart(deferred: Bool) {
        let calls = JobStartCounter()
        let handle: Int
        if deferred {
            let task = RuntimeAsyncTask()
            task.installLazyStartBody { calls.increment() }
            handle = runtimeRegisterObject(task)
        } else {
            let job = RuntimeJobHandle()
            job.installLazyStartBody { calls.increment() }
            handle = runtimeRegisterObject(job)
        }
        _ = kk_job_cancel(handle)
        #expect(kk_job_start(handle) == 0)
        #expect(kk_job_start(handle) == 0)
        #expect(calls.count == 0)
        #expect(kk_job_is_cancelled(handle) == 1)
        #expect(kk_job_is_completed(handle) == 1)
    }

    @Test(arguments: [false, true])
    func concurrentStartsClaimLazyBodyExactlyOnce(deferred: Bool) {
        let calls = JobStartCounter()
        let successes = JobStartCounter()
        let handle: Int
        if deferred {
            let task = RuntimeAsyncTask()
            task.installLazyStartBody { calls.increment() }
            handle = runtimeRegisterObject(task)
        } else {
            let job = RuntimeJobHandle()
            job.installLazyStartBody { calls.increment() }
            handle = runtimeRegisterObject(job)
        }
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            if kk_job_start(handle) == 1 { successes.increment() }
        }
        #expect(successes.count == 1)
        #expect(calls.count == 1)
        #expect(kk_job_is_active(handle) == 1)
        _ = kk_job_cancel(handle)
    }

    @Test
    func eagerBodylessAndNonCancellableJobsDoNotStartAgain() {
        let job = kk_job_new()
        #expect(kk_job_start(job) == 0)
        let wrapper = runtimeRegisterObject(RuntimeObjectBox(length: 0, classID: 1))
        _ = __kk_job_bind_wrapper(wrapper, job, runtimeNullSentinelInt)
        #expect(kk_job_start(wrapper) == 0)
        #expect(kk_job_is_active(wrapper) == 1)
        _ = kk_job_complete_unit(wrapper)
        #expect(kk_job_start(wrapper) == 0)
        #expect(kk_job_start(kk_non_cancellable_instance()) == 0)
        let task = RuntimeAsyncTask()
        task.markStarted()
        let handle = runtimeRegisterObject(task)
        #expect(kk_job_start(handle) == 0)
        task.complete(with: 0)
        #expect(kk_job_start(handle) == 0)
    }
}
