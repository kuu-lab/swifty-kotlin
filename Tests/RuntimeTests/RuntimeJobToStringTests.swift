import Foundation
@testable import Runtime
import Testing

/// KUU-1352: Job-family `toString()` renders kotlinx's `Name{State}@hex`
/// shape instead of the generic Any fallback's raw address integer.
@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeJobToStringTests {
    private func render(_ raw: Int) -> String {
        extractString(from: kk_any_to_string(raw, 0)) ?? "<nil>"
    }

    @Test
    func factoryJobsRenderKotlinxShape() {
        let jobRaw = kk_job_new()
        #expect(render(jobRaw) == "JobImpl{Active}@\(String(jobRaw, radix: 16))")
        #expect(runtimeRenderAnyForPrint(jobRaw) == "JobImpl{Active}@\(String(jobRaw, radix: 16))")

        let supervisorRaw = kk_supervisor_job_new()
        #expect(render(supervisorRaw) == "SupervisorJobImpl{Active}@\(String(supervisorRaw, radix: 16))")
    }

    @Test
    func rawHandleStatesRenderKotlinxNames() {
        let job = RuntimeJobHandle()
        job.debugName = "StandaloneCoroutine"
        let raw = Int(bitPattern: Unmanaged.passUnretained(job).toOpaque())

        // Deliberately unregistered from objectPointers: coroutine handles
        // resolve through the liveness registry instead.
        #expect(render(raw) == "StandaloneCoroutine{New}@\(String(raw, radix: 16))")

        job.markStarted()
        #expect(render(raw) == "StandaloneCoroutine{Active}@\(String(raw, radix: 16))")

        #expect(job.complete(with: 0))
        #expect(render(raw) == "StandaloneCoroutine{Completed}@\(String(raw, radix: 16))")
    }

    @Test
    func cancelledAndFailedJobsRenderCancelled() {
        // kotlinx prints Cancelling while a started job's cancellation is
        // still in flight (upstream's Finishing+isCancelling branch).
        let cancelling = RuntimeJobHandle()
        cancelling.debugName = "BlockingCoroutine"
        cancelling.markStarted()
        let cancellingRaw = Int(bitPattern: Unmanaged.passUnretained(cancelling).toOpaque())
        _ = cancelling.cancel(cause: 0)
        #expect(render(cancellingRaw) == "BlockingCoroutine{Cancelling}@\(String(cancellingRaw, radix: 16))")

        // A job cancelled before its body runs settles straight into
        // Cancelled, like the bodyless `Job()` factory result.
        let cancelled = RuntimeJobHandle()
        cancelled.debugName = "JobImpl"
        _ = cancelled.cancel(cause: 0)
        let cancelledRaw = Int(bitPattern: Unmanaged.passUnretained(cancelled).toOpaque())
        #expect(render(cancelledRaw) == "JobImpl{Cancelled}@\(String(cancelledRaw, radix: 16))")

        // kotlinx prints `Cancelled` for an exceptionally completed Deferred.
        let failed = RuntimeJobHandle()
        failed.debugName = "CompletableDeferredImpl"
        failed.markStarted()
        let failedRaw = Int(bitPattern: Unmanaged.passUnretained(failed).toOpaque())
        _ = failed.completeExceptionally(with: 1)
        #expect(render(failedRaw) == "CompletableDeferredImpl{Cancelled}@\(String(failedRaw, radix: 16))")
    }

    @Test
    func asyncTaskRendersThroughCompletionJob() {
        let task = RuntimeAsyncTask(debugName: "LazyDeferredCoroutine")
        let raw = Int(bitPattern: Unmanaged.passUnretained(task).toOpaque())
        #expect(render(raw) == "LazyDeferredCoroutine{New}@\(String(raw, radix: 16))")

        task.completionJob.markStarted()
        #expect(render(raw) == "LazyDeferredCoroutine{Active}@\(String(raw, radix: 16))")

        task.complete(with: 7)
        #expect(render(raw) == "LazyDeferredCoroutine{Completed}@\(String(raw, radix: 16))")
    }

    @Test
    func boundWrapperBoxRendersWrapperClassName() {
        let job = RuntimeJobHandle()
        job.markStarted()
        let wrapper = RuntimeObjectBox(
            length: 0,
            classID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CompletableJobImpl")
        )
        let wrapperRaw = runtimeRegisterObject(wrapper)
        let jobRaw = Int(bitPattern: Unmanaged.passUnretained(job).toOpaque())
        wrapper.coroutineJobHandle = jobRaw
        job.bindSourceWrapper(wrapper)
        job.nominalJobTypeID = runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CompletableJobImpl")

        // kotlinx's hexAddress identifies the Kotlin-side wrapper object.
        #expect(render(wrapperRaw) == "JobImpl{Active}@\(String(wrapperRaw, radix: 16))")
        // The bound job handle renders the same wrapper identity.
        #expect(render(jobRaw) == "JobImpl{Active}@\(String(wrapperRaw, radix: 16))")

        let deferredWrapper = RuntimeObjectBox(
            length: 0,
            classID: runtimeStableNominalTypeID(fqName: "kotlinx.coroutines.CompletableDeferredImpl")
        )
        let deferredRaw = runtimeRegisterObject(deferredWrapper)
        let deferredJob = RuntimeJobHandle()
        deferredJob.markStarted()
        let deferredJobRaw = Int(bitPattern: Unmanaged.passUnretained(deferredJob).toOpaque())
        deferredWrapper.coroutineJobHandle = deferredJobRaw
        deferredJob.bindSourceWrapper(deferredWrapper)
        deferredJob.nominalJobTypeID = runtimeStableNominalTypeID(
            fqName: "kotlinx.coroutines.CompletableDeferredImpl"
        )
        #expect(render(deferredRaw) == "CompletableDeferredImpl{Active}@\(String(deferredRaw, radix: 16))")
    }

    @Test
    func nonCancellableRendersBareName() {
        let raw = kk_non_cancellable_instance()
        #expect(render(raw) == "NonCancellable")
        #expect(runtimeRenderAnyForPrint(raw) == "NonCancellable")
    }

    @Test
    func nonJobValuesKeepExistingRendering() {
        #expect(render(42) == "42")
        let box = RuntimeObjectBox(length: 0, classID: 0)
        let boxRaw = runtimeRegisterObject(box)
        #expect(render(boxRaw) == "<object \(UnsafeMutableRawPointer(bitPattern: boxRaw)!)>")
    }
}
