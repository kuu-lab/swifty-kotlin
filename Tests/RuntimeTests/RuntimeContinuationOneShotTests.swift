import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - STDLIB-CORO-BUG-01: Resume-once (one-shot) guard tests
//
// Kotlin spec requires that a Continuation may be resumed at most once.
// A second `resume` must throw `IllegalStateException("Already resumed, ...")`.
// These tests verify the guard fires correctly for both the success path
// (resume(with:)) and the exception path (resume(withException:)), and that
// concurrent callers on separate threads are correctly serialised.

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeContinuationOneShotTests {
    // MARK: - Helpers

    /// Creates a fresh `RuntimeContinuationState` for testing without kicking
    /// off the full coroutine machinery.
    private func makeFreshState(functionID: Int64 = 9999) -> RuntimeContinuationState {
        RuntimeContinuationState(functionID: functionID)
    }

    /// Returns `true` if the raw `Int` pointer refers to a
    /// `RuntimeIllegalStateExceptionBox`.
    private func isIllegalStateException(_ raw: Int) -> Bool {
        guard raw != 0,
              let ptr = UnsafeMutableRawPointer(bitPattern: raw)
        else { return false }
        return tryCast(ptr, to: RuntimeIllegalStateExceptionBox.self) != nil
    }

    // MARK: - Basic one-shot guard: success value

    /// First `resume(with:)` returns nil (no error).
    @Test
    func firstResumeWithValueReturnsNil() {
        let state = makeFreshState()
        let result = state.resume(with: 42)
        #expect(result == nil, "First resume(with:) must succeed (return nil)")
    }

    /// Second `resume(with:)` returns an IllegalStateException.
    @Test
    func secondResumeWithValueReturnsIllegalStateException() {
        let state = makeFreshState()
        _ = state.resume(with: 42)
        let doubleResumeEx = state.resume(with: 99)
        #expect(doubleResumeEx != nil, "Second resume(with:) must return IllegalStateException")
        #expect(
            isIllegalStateException(doubleResumeEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    /// The IllegalStateException message must contain "Already resumed".
    @Test
    func doubleResumeWithValueExceptionMessage() throws {
        let state = makeFreshState()
        _ = state.resume(with: 7)
        let ex = try #require(state.resume(with: 13))
        let ptr = try #require(UnsafeMutableRawPointer(bitPattern: ex))
        let box = try #require(
            tryCast(ptr, to: RuntimeIllegalStateExceptionBox.self),
            "Exception is not an IllegalStateException box"
        )
        #expect(
            box.message?.contains("Already resumed") == true,
            "Exception message must contain 'Already resumed', got: \(box.message)"
        )
    }

    // MARK: - Basic one-shot guard: exception value

    /// First `resume(withException:)` returns nil (no error).
    @Test
    func firstResumeWithExceptionReturnsNil() {
        let state = makeFreshState()
        let ex = runtimeAllocateThrowable(message: "boom")
        let result = state.resume(withException: ex)
        #expect(result == nil, "First resume(withException:) must succeed (return nil)")
    }

    /// Second `resume(withException:)` (after first success resume) returns ISE.
    @Test
    func secondResumeWithExceptionAfterSuccessReturnsISE() {
        let state = makeFreshState()
        _ = state.resume(with: 1)
        let ex = runtimeAllocateThrowable(message: "boom2")
        let doubleEx = state.resume(withException: ex)
        #expect(doubleEx != nil, "Second resume(withException:) must return IllegalStateException")
        #expect(
            isIllegalStateException(doubleEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    /// Second `resume(withException:)` after first exception resume also returns ISE.
    @Test
    func secondResumeWithExceptionAfterExceptionReturnsISE() {
        let state = makeFreshState()
        let ex1 = runtimeAllocateThrowable(message: "first exception")
        _ = state.resume(withException: ex1)
        let ex2 = runtimeAllocateThrowable(message: "second exception")
        let doubleEx = state.resume(withException: ex2)
        #expect(doubleEx != nil, "Second resume(withException:) must return IllegalStateException")
        #expect(
            isIllegalStateException(doubleEx ?? 0),
            "Double-resume exception must be IllegalStateException"
        )
    }

    // MARK: - resetResumeState resets the guard

    /// After `resetResumeState()`, a fresh resume must succeed (no ISE).
    @Test
    func resetResumeStateAllowsSecondResumeToSucceed() {
        let state = makeFreshState()
        _ = state.resume(with: 1)
        // Simulate the coroutine loop advancing to the next suspend point
        state.resetResumeState()
        let result = state.resume(with: 2)
        #expect(result == nil, "resume(with:) after resetResumeState() must succeed")
    }

    // MARK: - deliverDoubleResumeException sets thrownException

    /// `deliverDoubleResumeException` must overwrite `thrownException` so that
    /// the coroutine body observes the violation when it next reads state.
    @Test
    func deliverDoubleResumeExceptionSetsThrownException() {
        let state = makeFreshState()
        _ = state.resume(with: 42)
        // Simulate what the C-level entry points do on double-resume.
        let ise = runtimeAllocateIllegalStateException(
            message: "Already resumed, but proposed with update 99"
        )
        state.deliverDoubleResumeException(ise)
        #expect(
            state.thrownException == ise,
            "deliverDoubleResumeException must store the ISE in thrownException"
        )
        #expect(state.completion == 0, "completion must be reset to 0 on double-resume")
    }

    // MARK: - C-level entry-point guard (kk_coroutine_continuation_resume)

    /// Calling `kk_coroutine_continuation_resume` twice must not crash and must
    /// surface the IllegalStateException via `thrownException` on the second call.
    @Test
    func cLevelResumeGuardSurfacesIllegalStateExceptionViaThrownException() throws {
        let continuation = kk_coroutine_continuation_new(8001)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        let state = try #require(
            runtimeContinuationState(from: continuation),
            "Could not retrieve RuntimeContinuationState for continuation"
        )

        // First resume: should succeed silently.
        kk_coroutine_continuation_resume(continuation, 42)
        #expect(state.thrownException == 0, "thrownException must be 0 after first resume")

        // Second resume: must deliver ISE via thrownException.
        kk_coroutine_continuation_resume(continuation, 99)
        #expect(
            isIllegalStateException(state.thrownException),
            "thrownException must be IllegalStateException after double-resume via C-level API"
        )
    }

    /// Calling `kk_coroutine_continuation_resume_with_exception` twice must
    /// surface ISE via `thrownException`.
    @Test
    func cLevelResumeWithExceptionGuardSurfacesISE() throws {
        let continuation = kk_coroutine_continuation_new(8002)
        defer { _ = kk_coroutine_state_exit(continuation, 0) }

        let state = try #require(
            runtimeContinuationState(from: continuation),
            "Could not retrieve RuntimeContinuationState"
        )

        let ex1 = runtimeAllocateThrowable(message: "first exception")
        kk_coroutine_continuation_resume_with_exception(continuation, ex1)
        #expect(state.thrownException == ex1, "First resume must store the original exception")

        let ex2 = runtimeAllocateThrowable(message: "second exception — double resume")
        kk_coroutine_continuation_resume_with_exception(continuation, ex2)
        #expect(
            isIllegalStateException(state.thrownException),
            "thrownException must be replaced with IllegalStateException after double resume-with-exception"
        )
    }

    // MARK: - Thread safety: concurrent double-resume

    /// Only one of two concurrent `resume(with:)` calls must succeed; the other
    /// must return an IllegalStateException.  This exercises the lock path.
    @Test
    func concurrentDoubleResumeOnlyOneSucceeds() {
        let iterations = 200
        var successCount = 0
        var failureCount = 0
        let countLock = NSLock()

        for _ in 0..<iterations {
            let state = makeFreshState()
            // Use a class wrapper to allow mutation from concurrent closures
            // while keeping Sendable conformance. The NSLock below guards access.
            final class ResultsBox: @unchecked Sendable {
                var values: [Int?] = [nil, nil]
            }
            let resultsBox = ResultsBox()
            let group = DispatchGroup()

            for i in 0..<2 {
                group.enter()
                DispatchQueue.global().async {
                    let ex = state.resume(with: 1)
                    countLock.lock()
                    resultsBox.values[i] = ex
                    countLock.unlock()
                    group.leave()
                }
            }
            group.wait()

            let results = resultsBox.values
            let wins = results.filter { $0 == nil }.count
            let losses = results.filter { $0 != nil }.count
            countLock.lock()
            successCount += wins
            failureCount += losses
            countLock.unlock()
        }

        #expect(
            successCount == iterations,
            "Exactly one resume per pair must succeed across \(iterations) iterations"
        )
        #expect(
            failureCount == iterations,
            "Exactly one resume per pair must fail across \(iterations) iterations"
        )
    }
}
