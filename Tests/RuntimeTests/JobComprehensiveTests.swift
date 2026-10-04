import Dispatch
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct JobComprehensiveTests {
    // MARK: - Job State Transitions Tests

    @Test func jobStateTransitionsCompleteLifecycle() {
        let job = RuntimeJobHandle()

        // Initial state: New
        #expect(!job.isActiveSnapshot())
        #expect(!job.completedSnapshot())
        #expect(!job.cancellationSnapshot())

        // Start job
        job.markStarted()
        #expect(job.isActiveSnapshot())
        #expect(!job.completedSnapshot())
        #expect(!job.cancellationSnapshot())

        // Complete normally
        #expect(job.complete(with: 42))
        #expect(!job.isActiveSnapshot())
        #expect(job.completedSnapshot())
        #expect(!job.cancellationSnapshot())
        #expect(job.join() == 42)
    }

    @Test func jobStateTransitionsCancellationLifecycle() {
        let job = RuntimeJobHandle()

        // Start job
        job.markStarted()
        #expect(job.isActiveSnapshot())

        // Cancel job
        #expect(job.cancel())
        #expect(!job.isActiveSnapshot())
        #expect(job.cancellationSnapshot())

        // Complete cancellation
        #expect(job.complete(with: 0))
        #expect(job.completedSnapshot())
        #expect(job.cancellationSnapshot())
    }

    @Test func jobStateTransitionsExceptionalFailure() {
        let job = RuntimeJobHandle()
        job.markStarted()

        let exception = runtimeAllocateThrowable(message: "test error")
        #expect(job.completeExceptionally(with: exception))

        #expect(!job.isActiveSnapshot())
        #expect(job.completedSnapshot())
        #expect(job.isFailedSnapshot())
        #expect(!job.cancellationSnapshot())
        #expect(job.join() == exception)
    }

    // MARK: - Job Hierarchy Tests

    @Test func jobParentChildRelationship() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()

        parent.markStarted()
        child.markStarted()

        // Establish parent-child relationship
        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)

        // Cancel parent should propagate to child
        #expect(parent.cancel())
        #expect(parent.cancellationSnapshot())
        #expect(child.cancellationSnapshot())
    }

    @Test func jobChildRegistrationAfterParentCancelled() {
        let parent = RuntimeJobHandle()
        let child = RuntimeJobHandle()

        parent.markStarted()
        child.markStarted()

        // Cancel parent first
        #expect(parent.cancel())

        // Then register child - should be cancelled immediately
        let childHandle = Int(bitPattern: Unmanaged.passUnretained(child).toOpaque())
        parent.registerChild(childHandle)

        #expect(child.cancellationSnapshot())
    }

    // MARK: - Job Cancellation Tests

    @Test func jobCancelWithCause() {
        let job = RuntimeJobHandle()
        job.markStarted()

        let cause = runtimeAllocateThrowable(message: "cancellation cause")
        #expect(job.cancel(cause: cause))

        #expect(job.cancellationSnapshot())
        #expect(job.complete(with: 0))
        #expect(job.join() == cause)
    }

    @Test func jobCancelIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()

        // First cancel should succeed
        #expect(job.cancel())

        // Subsequent cancels should return false
        #expect(!job.cancel())

        let cause = runtimeAllocateThrowable(message: "test")
        #expect(!job.cancel(cause: cause))
    }

    @Test func jobCancelAfterComplete() {
        let job = RuntimeJobHandle()
        job.markStarted()

        // Complete first
        #expect(job.complete(with: 42))
        #expect(job.completedSnapshot())

        // Then cancel should fail
        #expect(!job.cancel())
    }

    // MARK: - Job Completion Tests

    @Test func jobCompleteIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()

        // First complete should succeed
        #expect(job.complete(with: 42))

        // Subsequent completes should fail
        #expect(!job.complete(with: 100))
        #expect(!job.completeExceptionally(with: runtimeAllocateThrowable(message: "error")))
    }

    @Test func jobCompleteExceptionallyIdempotent() {
        let job = RuntimeJobHandle()
        job.markStarted()

        let exception = runtimeAllocateThrowable(message: "test error")
        #expect(job.completeExceptionally(with: exception))

        // Subsequent completions should fail
        #expect(!job.complete(with: 42))
        #expect(!job.completeExceptionally(with: runtimeAllocateThrowable(message: "another error")))
    }

    // MARK: - Job Join Tests

    @Test func jobJoinReturnsCorrectValue() {
        let job = RuntimeJobHandle()
        job.markStarted()

        // Normal completion
        #expect(job.complete(with: 123))
        #expect(job.join() == 123)

        // Exceptional completion
        let job2 = RuntimeJobHandle()
        job2.markStarted()
        let exception = runtimeAllocateThrowable(message: "error")
        #expect(job2.completeExceptionally(with: exception))
        #expect(job2.join() == exception)

        // Cancellation
        let job3 = RuntimeJobHandle()
        job3.markStarted()
        let cause = runtimeAllocateThrowable(message: "cancelled")
        #expect(job3.cancel(cause: cause))
        #expect(job3.complete(with: 0))
        #expect(job3.join() == cause)
    }

    @Test func jobAwaitCompletionSameAsJoin() {
        let job = RuntimeJobHandle()
        job.markStarted()

        #expect(job.complete(with: 456))
        #expect(job.awaitCompletion() == 456)
        #expect(job.join() == 456)
    }

    // MARK: - ABI Function Tests

    @Test func abiJobStateQueries() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())

        // Initial state
        #expect(kk_job_is_active(jobHandle) == 0)
        #expect(kk_job_is_completed(jobHandle) == 0)
        #expect(kk_job_is_cancelled(jobHandle) == 0)
        #expect(kk_job_is_failed(jobHandle) == 0)

        // Start job
        job.markStarted()
        #expect(kk_job_is_active(jobHandle) == 1)
        #expect(kk_job_is_completed(jobHandle) == 0)
        #expect(kk_job_is_cancelled(jobHandle) == 0)
        #expect(kk_job_is_failed(jobHandle) == 0)

        // Complete job
        #expect(job.complete(with: 789))
        #expect(kk_job_is_active(jobHandle) == 0)
        #expect(kk_job_is_completed(jobHandle) == 1)
        #expect(kk_job_is_cancelled(jobHandle) == 0)
        #expect(kk_job_is_failed(jobHandle) == 0)

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }

    @Test func abiJobFailedState() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())

        job.markStarted()

        // Complete with exception
        let exception = runtimeAllocateThrowable(message: "test error")
        #expect(job.completeExceptionally(with: exception))

        #expect(kk_job_is_active(jobHandle) == 0)
        #expect(kk_job_is_completed(jobHandle) == 1)
        #expect(kk_job_is_cancelled(jobHandle) == 0)
        #expect(kk_job_is_failed(jobHandle) == 1)

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }

    @Test func abiCancelFunctions() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())

        job.markStarted()

        // Normal cancel
        #expect(kk_job_cancel(jobHandle) == 0)
        #expect(job.cancellationSnapshot())

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }

    @Test func abiCompleteFunctions() {
        let job = RuntimeJobHandle()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())

        job.markStarted()

        // Normal complete
        #expect(kk_job_complete(jobHandle, 999) == 1)
        #expect(job.completedSnapshot())

        // Exceptional complete (new job)
        let job2 = RuntimeJobHandle()
        let job2Handle = Int(bitPattern: Unmanaged.passRetained(job2).toOpaque())
        job2.markStarted()

        let exception = runtimeAllocateThrowable(message: "test")
        #expect(kk_job_complete_exceptionally(job2Handle, exception) == 1)
        #expect(job2.isFailedSnapshot())

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: job2Handle)!).release()
    }

    // MARK: - AsyncTask Job Compatibility Tests

    @Test func asyncTaskJobInterfaceCompatibility() {
        let task = RuntimeAsyncTask()
        let taskHandle = Int(bitPattern: Unmanaged.passRetained(task).toOpaque())

        // Initial state
        #expect(kk_job_is_active(taskHandle) == 0)
        #expect(kk_job_is_completed(taskHandle) == 0)
        #expect(kk_job_is_cancelled(taskHandle) == 0)

        // Complete task
        task.complete(with: 555)
        #expect(kk_job_is_active(taskHandle) == 0)
        #expect(kk_job_is_completed(taskHandle) == 1)
        #expect(kk_job_is_cancelled(taskHandle) == 0)

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: taskHandle)!).release()
    }

    // MARK: - Edge Cases Tests

    @Test func jobInvalidHandleHandling() {
        // Invalid handles should not crash
        #expect(kk_job_is_active(0) == 0)
        #expect(kk_job_is_completed(0) == 1) // Invalid treated as completed
        #expect(kk_job_is_cancelled(0) == 1) // Invalid treated as cancelled
        #expect(kk_job_join(0, 0) == 0)
        #expect(kk_job_await_completion(0, 0) == 0)
    }

    @Test func jobConcurrentAccess() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let jobHandle = Int(bitPattern: Unmanaged.passRetained(job).toOpaque())

        let group = DispatchGroup()

        // Concurrent state queries
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                let active = kk_job_is_active(jobHandle)
                let completed = kk_job_is_completed(jobHandle)
                let cancelled = kk_job_is_cancelled(jobHandle)

                // Should not crash and return valid boolean values
                #expect(active == 0 || active == 1)
                #expect(completed == 0 || completed == 1)
                #expect(cancelled == 0 || cancelled == 1)

                group.leave()
            }
        }

        #expect(group.wait(timeout: .now() + 5.0) == .success)

        // Clean up
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: jobHandle)!).release()
    }
}
