import Dispatch
import Foundation
@testable import Runtime
import Testing

@Suite
struct RuntimeHelpersTests {
    // MARK: - Null sentinel constants

    @Test func nullSentinelInt64EqualsInt64Min() {
        #expect(runtimeNullSentinelInt64 == Int64.min)
    }

    @Test func nullSentinelIntTruncatesFromInt64Min() {
        #expect(runtimeNullSentinelInt == Int(truncatingIfNeeded: Int64.min))
    }

    // MARK: - normalizeNullableRuntimePointer

    @Test func normalizeNilPointerReturnsNil() {
        let result = normalizeNullableRuntimePointer(nil)
        #expect(result == nil)
    }

    @Test(.enabled(if: runtimeNullSentinelInt != 0))
    func normalizeNullSentinelPointerReturnsNil() throws {
        let sentinelPtr = try #require(UnsafeMutableRawPointer(bitPattern: runtimeNullSentinelInt))
        let result = normalizeNullableRuntimePointer(sentinelPtr)
        #expect(result == nil, "Null sentinel should be normalized to nil")
    }

    @Test func normalizeValidPointerReturnsItself() {
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { ptr.deallocate() }
        ptr.storeBytes(of: 42, as: Int.self)
        let result = normalizeNullableRuntimePointer(ptr)
        #expect(result == ptr)
    }

    // MARK: - runtimeAllocateThrowable

    @Test func allocateThrowableReturnsNonZeroHandle() {
        let handle = runtimeAllocateThrowable(message: "test error")
        #expect(handle != 0)
    }

    @Test func allocateThrowableWithDifferentMessagesReturnsDifferentHandles() {
        let handle1 = runtimeAllocateThrowable(message: "error 1")
        let handle2 = runtimeAllocateThrowable(message: "error 2")
        #expect(handle1 != handle2)
    }

    @Test func allocateThrowableRegistersInObjectPointers() throws {
        let handle = runtimeAllocateThrowable(message: "registered")
        #expect(handle != 0)
        // Confirm the handle is a valid object pointer by attempting to cast it.
        let ptr = try #require(
            UnsafeMutableRawPointer(bitPattern: handle),
            "Expected non-nil raw pointer from handle"
        )
        let box = tryCast(ptr, to: RuntimeThrowableBox.self)
        #expect(box != nil, "Handle should point to a RuntimeThrowableBox")
        #expect(box?.message == "registered")
    }

    // MARK: - tryCast

    @Test func tryCastSucceedsForMatchingType() {
        let box = RuntimeStringBox("test")
        let unmanaged = Unmanaged.passRetained(box)
        let ptr = UnsafeMutableRawPointer(unmanaged.toOpaque())
        defer { unmanaged.release() }

        let result = tryCast(ptr, to: RuntimeStringBox.self)
        #expect(result != nil)
        #expect(result?.value == "test")
    }

    @Test func tryCastReturnsNilForWrongType() {
        let box = RuntimeIntBox(42)
        let unmanaged = Unmanaged.passRetained(box)
        let ptr = UnsafeMutableRawPointer(unmanaged.toOpaque())
        defer { unmanaged.release() }

        let result = tryCast(ptr, to: RuntimeStringBox.self)
        #expect(result == nil)
    }

    // MARK: - KKDispatchContinuation

    @Test func dispatchContinuationStoresContext() {
        let ptr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { ptr.deallocate() }
        ptr.storeBytes(of: 99, as: Int.self)
        let continuation = KKDispatchContinuation(context: ptr) { _ in }
        #expect(continuation.context == ptr)
    }

    @Test func dispatchContinuationNilContext() {
        let continuation = KKDispatchContinuation(context: nil) { _ in }
        #expect(continuation.context == nil)
    }

    @Test func dispatchContinuationResumeInvokesCallback() {
        var called = false
        let continuation = KKDispatchContinuation(context: nil) { _ in
            called = true
        }
        continuation.resumeWith(nil)
        #expect(called)
    }

    @Test func dispatchContinuationResumePassesResultToCallback() {
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: nil) { result in
            receivedResult = result
        }
        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 7, as: Int.self)
        continuation.resumeWith(resultPtr)
        #expect(receivedResult == resultPtr)
    }

    @Test func continuationInterceptedReturnsSelfWhenContextHasNoDispatcher() {
        let continuation = KKDispatchContinuation(context: nil) { _ in }
        let intercepted = continuation.intercepted()

        let isSameInstance = (intercepted as AnyObject) === (continuation as AnyObject)
        #expect(
            isSameInstance,
            "Continuation without a dispatcher should not be wrapped"
        )
    }

    @Test func continuationInterceptedDispatchesThroughDispatcherContext() {
        let dispatched = DispatchSemaphore(value: 0)
        let dispatcherContext = UnsafeMutableRawPointer(bitPattern: kk_dispatcher_default())
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: dispatcherContext) { result in
            receivedResult = result
            dispatched.signal()
        }

        let intercepted = continuation.intercepted()

        let isDistinctInstance = (intercepted as AnyObject) !== (continuation as AnyObject)
        #expect(
            isDistinctInstance,
            "Continuation with a dispatcher should be wrapped"
        )

        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 123, as: Int.self)

        intercepted.resumeWith(resultPtr)
        #expect(dispatched.wait(timeout: .now() + 2.0) == .success)
        #expect(receivedResult == resultPtr)
    }

    @Test func explicitContinuationInterceptorBridgeDispatchesContinuation() throws {
        let dispatched = DispatchSemaphore(value: 0)
        var receivedResult: UnsafeMutableRawPointer?
        let continuation = KKDispatchContinuation(context: nil) { result in
            receivedResult = result
            dispatched.signal()
        }
        let continuationRaw = Int(bitPattern: Unmanaged.passUnretained(continuation as AnyObject).toOpaque())
        let interceptedRaw = kk_continuation_interceptor_intercept_continuation(kk_dispatcher_default(), continuationRaw)

        #expect(
            interceptedRaw != continuationRaw,
            "Explicit interceptor bridge should wrap the continuation when a dispatcher is available"
        )

        let interceptedPtr = try #require(
            UnsafeMutableRawPointer(bitPattern: interceptedRaw),
            "Expected wrapped continuation pointer"
        )
        let interceptedObject = Unmanaged<AnyObject>.fromOpaque(interceptedPtr).takeUnretainedValue()
        let intercepted = try #require(
            interceptedObject as? KKContinuation,
            "Expected wrapped object to be a KKContinuation"
        )

        let resultPtr = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<Int>.size,
            alignment: MemoryLayout<Int>.alignment
        )
        defer { resultPtr.deallocate() }
        resultPtr.storeBytes(of: 456, as: Int.self)

        intercepted.resumeWith(resultPtr)
        #expect(dispatched.wait(timeout: .now() + 2.0) == .success)
        #expect(receivedResult == resultPtr)
    }

    // MARK: - KxMiniRuntime.runBlocking

    @Test func runBlockingBlocksUntilCallbackInvoked() {
        let callbackInvoked = DispatchSemaphore(value: 0)
        let runBlockingReturned = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            KxMiniRuntime.runBlocking { done in
                callbackInvoked.signal()
                done(nil)
            }
            runBlockingReturned.signal()
        }

        #expect(callbackInvoked.wait(timeout: .now() + 2.0) == .success)
        #expect(runBlockingReturned.wait(timeout: .now() + 2.0) == .success)
    }

    @Test func runBlockingCompletesWhenCallbackCalledAsync() {
        let callbackInvoked = DispatchSemaphore(value: 0)
        let runBlockingReturned = DispatchSemaphore(value: 0)
        final class CountBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0

            func set(_ newValue: Int) {
                lock.lock()
                value = newValue
                lock.unlock()
            }

            func get() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }
        let count = CountBox()

        DispatchQueue.global().async {
            KxMiniRuntime.runBlocking { done in
                DispatchQueue.global().async(execute: DispatchWorkItem {
                    count.set(42)
                    callbackInvoked.signal()
                    done(nil)
                })
            }
            runBlockingReturned.signal()
        }

        #expect(callbackInvoked.wait(timeout: .now() + 2.0) == .success)
        #expect(runBlockingReturned.wait(timeout: .now() + 2.0) == .success)
        #expect(count.get() == 42)
    }

    // MARK: - KxMiniRuntime.launch

    @Test func launchExecutesBlock() {
        let executed = DispatchSemaphore(value: 0)
        KxMiniRuntime.launch {
            executed.signal()
        }
        #expect(executed.wait(timeout: .now() + 2.0) == .success)
    }

    // MARK: - KxMiniRuntime.async

    @Test func asyncReturnsKKContinuation() {
        let continuation: KKContinuation? = KxMiniRuntime.async { nil }
        #expect(continuation != nil)
    }

    // MARK: - KxMiniRuntime.delay

    @Test func delayInvokesContinuationAfterDelay() {
        let invoked = DispatchSemaphore(value: 0)
        let continuation = KKDispatchContinuation(context: nil) { _ in
            invoked.signal()
        }
        KxMiniRuntime.delay(milliseconds: 10, continuation: continuation)
        #expect(invoked.wait(timeout: .now() + 3.0) == .success)
    }

    @Test func delayWithZeroMilliseconds() {
        let invoked = DispatchSemaphore(value: 0)
        let continuation = KKDispatchContinuation(context: nil) { _ in
            invoked.signal()
        }
        KxMiniRuntime.delay(milliseconds: 0, continuation: continuation)
        #expect(invoked.wait(timeout: .now() + 3.0) == .success)
    }

    @Test func delayWithNegativeMilliseconds() {
        let invoked = DispatchSemaphore(value: 0)
        let continuation = KKDispatchContinuation(context: nil) { _ in
            invoked.signal()
        }
        KxMiniRuntime.delay(milliseconds: -5, continuation: continuation)
        #expect(invoked.wait(timeout: .now() + 3.0) == .success)
    }
}
