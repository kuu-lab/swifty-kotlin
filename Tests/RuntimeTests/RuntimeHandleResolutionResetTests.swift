#if canImport(Testing)
import Dispatch
import Foundation
@testable import Runtime
import Testing

/// A process-global runtime reset must not invalidate handles of boxes the
/// runtime still retains. Swift Testing suites share one process, so an
/// isolation reset from one suite used to clear `objectPointers` while another
/// suite still owned live range / array / string handles, and the next use of
/// such a handle aborted the whole test process with a KSWIFTK-RUNTIME-0001
/// invalid-handle panic (`__kk_range_random`, `kk_native_byteArray_getLongAt`,
/// `runtimeStringUTF16CodeUnits`).
@Suite(.serialized, .runtimeIsolation(.all))
struct RuntimeHandleResolutionResetTests {
    @Test
    func testRangeHandleStaysUsableAcrossGCReset() {
        let range = kk_op_rangeTo(1, 5)

        #expect(kk_runtime_reset_gc())

        #expect(runtimeRangeBox(from: range) != nil)
        var thrown = 0
        let value = __kk_range_random(range, &thrown)
        #expect(thrown == 0)
        #expect((1...5).contains(value))
    }

    @Test
    func testArrayHandleStaysUsableAcrossGCReset() {
        let array = kk_array_new(8)
        for index in 0..<8 {
            _ = kk_array_set(array, index, index + 1, nil)
        }

        #expect(kk_runtime_reset_gc())

        #expect(runtimeArrayBox(from: array) != nil)
        #expect(kk_native_byteArray_getLongAt(array, 0) == 0x0807_0605_0403_0201)
    }

    @Test
    func testStringHandleStaysUsableAcrossGCReset() {
        let string = makeString("ab")

        #expect(kk_runtime_reset_gc())

        #expect(runtimeStringFromRaw(string) == "ab")
        #expect(runtimeStringUTF16CodeUnits(string) == Array("ab".utf16))
    }

    /// A full reset releases the boxes it owns (KClass cache, thread locals), so
    /// their handles must stop resolving instead of pointing at freed memory.
    @Test
    func testResetDropsRegistrationOfBoxesItReleases() {
        let threadLocal = __kk_thread_local_new()
        let kClass = __kk_kclass_create(0x1234_5678, makeString("Sample"))
        #expect(runtimeIsObjectPointerRaw(threadLocal))
        #expect(runtimeIsObjectPointerRaw(kClass))

        #expect(runtimeTryForceReset())

        #expect(!runtimeIsObjectPointerRaw(threadLocal))
        #expect(!runtimeIsObjectPointerRaw(kClass))
    }

    /// Handles created concurrently with repeated resets must all stay usable:
    /// this is the shape of the CI flake, where one suite reset global state
    /// while another suite was resolving its own freshly created handles.
    @Test
    func testHandlesStayUsableWhileAnotherThreadResetsGlobalState() {
        let resetsFinished = DispatchSemaphore(value: 0)
        let successfulReset = DispatchSemaphore(value: 0)
        let startResets = DispatchSemaphore(value: 0)
        let firstRange = kk_op_rangeTo(1, 5)
        DispatchQueue.global(qos: .userInitiated).async {
            startResets.wait()
            for _ in 0..<500 {
                if kk_runtime_reset_gc() { successfulReset.signal() }
            }
            resetsFinished.signal()
        }
        startResets.signal()
        #expect(successfulReset.wait(timeout: .now() + 5) == .success)
        #expect(runtimeRangeBox(from: firstRange) != nil)

        for _ in 0..<500 {
            let range = kk_op_rangeTo(1, 5)
            var thrown = 0
            let value = __kk_range_random(range, &thrown)
            #expect(thrown == 0)
            #expect((1...5).contains(value))

            let string = makeString("xy")
            #expect(runtimeStringUTF16CodeUnits(string) == Array("xy".utf16))
        }

        #expect(resetsFinished.wait(timeout: .now() + 60) == .success)
    }

    private func makeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func runtimeIsObjectPointerRaw(_ raw: Int) -> Bool {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
            return false
        }
        return runtimeIsObjectPointer(ptr)
    }
}
#endif
