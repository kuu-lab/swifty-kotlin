import Dispatch
import Foundation
@testable import Runtime
import XCTest

/// A process-global runtime reset must not invalidate handles of boxes the
/// runtime still retains. Swift Testing suites share one process, so an
/// isolation reset from one suite used to clear `objectPointers` while another
/// suite still owned live range / array / string handles, and the next use of
/// such a handle aborted the whole test process with a KSWIFTK-RUNTIME-0001
/// invalid-handle panic (`kk_range_random`, `kk_native_byteArray_getLongAt`,
/// `runtimeStringUTF16CodeUnits`).
final class RuntimeHandleResolutionResetTests: IsolatedRuntimeXCTestCase {
    func testRangeHandleStaysUsableAcrossGCReset() {
        let range = kk_op_rangeTo(1, 5)

        kk_runtime_reset_gc()

        XCTAssertNotNil(runtimeRangeBox(from: range))
        var thrown = 0
        let value = kk_range_random(range, &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertTrue((1...5).contains(value))
    }

    func testArrayHandleStaysUsableAcrossGCReset() {
        let array = kk_array_new(8)
        for index in 0..<8 {
            _ = kk_array_set(array, index, index + 1, nil)
        }

        kk_runtime_reset_gc()

        XCTAssertNotNil(runtimeArrayBox(from: array))
        XCTAssertEqual(kk_native_byteArray_getLongAt(array, 0), 0x0807_0605_0403_0201)
    }

    func testStringHandleStaysUsableAcrossGCReset() {
        let string = makeString("ab")

        kk_runtime_reset_gc()

        XCTAssertEqual(runtimeStringFromRaw(string), "ab")
        XCTAssertEqual(runtimeStringUTF16CodeUnits(string), Array("ab".utf16))
    }

    /// A full reset releases the boxes it owns (KClass cache, thread locals), so
    /// their handles must stop resolving instead of pointing at freed memory.
    func testResetDropsRegistrationOfBoxesItReleases() {
        let threadLocal = kk_thread_local_new()
        let kClass = __kk_kclass_create(0x1234_5678, makeString("Sample"))
        XCTAssertTrue(runtimeIsObjectPointerRaw(threadLocal))
        XCTAssertTrue(runtimeIsObjectPointerRaw(kClass))

        kk_runtime_force_reset()

        XCTAssertFalse(runtimeIsObjectPointerRaw(threadLocal))
        XCTAssertFalse(runtimeIsObjectPointerRaw(kClass))
    }

    /// Handles created concurrently with repeated resets must all stay usable:
    /// this is the shape of the CI flake, where one suite reset global state
    /// while another suite was resolving its own freshly created handles.
    func testHandlesStayUsableWhileAnotherThreadResetsGlobalState() {
        let resetsFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<500 {
                kk_runtime_reset_gc()
            }
            resetsFinished.signal()
        }

        for _ in 0..<500 {
            let range = kk_op_rangeTo(1, 5)
            var thrown = 0
            let value = kk_range_random(range, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertTrue((1...5).contains(value))

            let string = makeString("xy")
            XCTAssertEqual(runtimeStringUTF16CodeUnits(string), Array("xy".utf16))
        }

        XCTAssertEqual(resetsFinished.wait(timeout: .now() + 60), .success)
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
