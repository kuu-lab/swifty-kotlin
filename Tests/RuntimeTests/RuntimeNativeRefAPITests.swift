@testable import Runtime
import XCTest

// STDLIB-NATIVE-REF-001: Inventory of kotlin.native.ref / kotlin.native.runtime APIs.
//
// This file documents what is implemented vs. what is missing in the KSwiftK
// runtime with respect to the Kotlin/Native standard library API surface.
//
// IMPLEMENTED (tested here):
//   kotlin.native.runtime namespace (via java.lang / System shims):
//     - System.gc()              -> kk_system_gc()     (calls kk_gc_collect internally)
//     - Runtime.getRuntime()     -> kk_runtime_getRuntime()
//     - Runtime.totalMemory()    -> kk_runtime_totalMemory()
//     - Runtime.freeMemory()     -> kk_runtime_freeMemory()
//     - Runtime.maxMemory()      -> kk_runtime_maxMemory()
//
//   kotlin.native.ref shim (via kk_pin / kk_freeze):
//     - Pinned<T> (pin / unpin / get) -> kk_pin_object / kk_unpin_object / kk_pinned_get
//     - freeze() / isFrozen            -> kk_freeze_object / kk_is_frozen
//
//   kotlin.native.runtime.GC (via kk_gc_collect):
//     - GC.collect()  -> kk_gc_collect()  [no Kotlin-level GC object, raw C entry]
//
//   kotlin.native.runtime.Debugging (via kk_assertions_* entry points):
//     - Debugging.areAssertionsEnabled    -> kk_assertions_enabled()
//     - Debugging.setAssertionsEnabled()  -> kk_assertions_set_enabled()
//
// MISSING (not implemented — no runtime entry point or compiler-side stub):
//   - kotlin.native.ref.WeakReference<T>  (no kk_weak_ref_* entry points)
//   - kotlin.native.ref.WeakReference.get()
//   - kotlin.native.ref.WeakReference.clear()
//   - createCleaner { } (no kk_cleaner_* entry points)
//   - kotlin.native.runtime.GC.targetHeapBytes (property, not exposed)
//   - kotlin.native.runtime.GC.targetHeapUtilization (property, not exposed)
//   - kotlin.native.runtime.GC.maxHeapBytes (property, not exposed)
//   - kotlin.native.runtime.GC.schedule() (separate from collect, not exposed)
//   - kotlin.native.runtime.Debugging.gcSuspendCount
//   - kotlin.native.runtime.Debugging.threadCount
//   - kotlin.native.runtime.Debugging.globalObjectCount

final class RuntimeNativeRefGCTests: IsolatedRuntimeXCTestCase {

    // MARK: - GC.collect() (kk_gc_collect)

    func testGCCollectIsCallableWithoutCrashing() {
        // Calling kk_gc_collect must not crash; it returns void.
        kk_gc_collect()
    }

    func testGCCollectMultipleTimesIsIdempotent() {
        for _ in 0 ..< 3 {
            kk_gc_collect()
        }
    }

    func testSystemGCDelegatesToGCCollect() {
        // kk_system_gc() is the Kotlin-facing alias; must be callable without crash.
        kk_system_gc()
    }

    func testGCCollectOnEmptyHeapIsNoOp() {
        // When no heap objects exist, collect should succeed immediately.
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
        kk_gc_collect()
        XCTAssertEqual(kk_runtime_heap_object_count(), 0)
    }
}

final class RuntimeNativeRefMemoryTests: XCTestCase {

    // MARK: - Runtime memory API (maps to kotlin.native.runtime GC memory properties)

    func testRuntimeGetRuntimeReturnsNonZeroStableHandle() {
        let h1 = kk_runtime_getRuntime()
        let h2 = kk_runtime_getRuntime()
        XCTAssertNotEqual(h1, 0, "getRuntime() must return a non-null handle")
        XCTAssertEqual(h1, h2, "getRuntime() must return the same singleton handle")
    }

    func testTotalMemoryIsPositive() {
        let total = kk_runtime_totalMemory()
        XCTAssertGreaterThan(total, 0, "totalMemory() must return a positive value")
    }

    func testFreeMemoryIsNonNegative() {
        let free = kk_runtime_freeMemory()
        XCTAssertGreaterThanOrEqual(free, 0, "freeMemory() must be >= 0")
    }

    func testMaxMemoryIsAtLeastTotalMemory() {
        let max = kk_runtime_maxMemory()
        let total = kk_runtime_totalMemory()
        XCTAssertGreaterThanOrEqual(max, total, "maxMemory() must be >= totalMemory()")
    }

    func testMaxMemoryIsPositive() {
        // Maps to kotlin.native.runtime.GC.targetHeapBytes analogue — a positive
        // upper bound is always available even if the Kotlin property is missing.
        let max = kk_runtime_maxMemory()
        XCTAssertGreaterThan(max, 0, "maxMemory() must be positive (covers targetHeapBytes analogue)")
    }
}

final class RuntimeNativeRefPinnedTests: IsolatedRuntimeXCTestCase {

    // MARK: - Pinned<T> — kotlin.native.ref.Pinned (kk_pin / kk_unpin / kk_pinned_get)

    private func withDummyTypeInfo(_ body: (UnsafeRawPointer) -> Void) {
        let typeName = Array("Pinned.Test\0".utf8).map(CChar.init)
        let fieldOffsets = [UInt32(0)]
        typeName.withUnsafeBufferPointer { nameBuffer in
            fieldOffsets.withUnsafeBufferPointer { offsetBuffer in
                var dummy = UnsafeRawPointer(bitPattern: 0x1)!
                withUnsafePointer(to: &dummy) { vtablePtr in
                    var typeInfo = KTypeInfo(
                        fqName: nameBuffer.baseAddress!,
                        instanceSize: 0,
                        fieldCount: 0,
                        fieldOffsets: offsetBuffer.baseAddress!,
                        vtableSize: 0,
                        vtable: vtablePtr,
                        itable: nil,
                        gcDescriptor: nil
                    )
                    withUnsafePointer(to: &typeInfo) { typeInfoPtr in
                        body(UnsafeRawPointer(typeInfoPtr))
                    }
                }
            }
        }
    }

    func testPinObjectReturnsPinnedHandle() {
        withDummyTypeInfo { ti in
            let obj = Int(bitPattern: kk_alloc(16, ti))
            let pinHandle = kk_pin_object(obj)
            XCTAssertNotEqual(pinHandle, 0, "kk_pin_object must return a non-zero handle")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testPinnedGetReturnsOriginalObject() {
        withDummyTypeInfo { ti in
            let obj = Int(bitPattern: kk_alloc(16, ti))
            let pinHandle = kk_pin_object(obj)
            let retrieved = kk_pinned_get(pinHandle)
            XCTAssertEqual(retrieved, obj, "kk_pinned_get must return the same object that was pinned")
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testUnpinObjectReturnsOriginalObjectRaw() {
        withDummyTypeInfo { ti in
            let obj = Int(bitPattern: kk_alloc(16, ti))
            let pinHandle = kk_pin_object(obj)
            let unpinned = kk_unpin_object(pinHandle)
            XCTAssertEqual(unpinned, obj, "kk_unpin_object must return the original object raw value")
        }
    }

    func testPinObjectPreservesObjectDuringGC() {
        withDummyTypeInfo { ti in
            let obj = Int(bitPattern: kk_alloc(16, ti))
            let pinHandle = kk_pin_object(obj)
            // Object is not reachable via global root / frame, only via pin.
            // The runtime tracks pinned objects via ARC retain, so GC must not collect it.
            kk_gc_collect()
            // Verify we can still retrieve it without crash.
            let retrieved = kk_pinned_get(pinHandle)
            XCTAssertEqual(retrieved, obj)
            _ = kk_unpin_object(pinHandle)
        }
    }

    func testPinZeroObjectReturnsZero() {
        let handle = kk_pin_object(0)
        XCTAssertEqual(handle, 0, "Pinning the null (0) object must return 0")
    }
}

final class RuntimeNativeRefFreezeTests: XCTestCase {

    // MARK: - freeze() / isFrozen — kotlin.native legacy immutability

    func testFreezeObjectMarksItAsFrozen() {
        let fakeRaw = 0xABCD1234
        _ = kk_freeze_object(fakeRaw)
        XCTAssertEqual(kk_is_frozen(fakeRaw), 1, "Object must be frozen after kk_freeze_object")
    }

    func testUnfrozenObjectReportsNotFrozen() {
        let fakeRaw = 0xDEAD5678
        XCTAssertEqual(kk_is_frozen(fakeRaw), 0, "Object must not be frozen before kk_freeze_object")
    }

    func testFreezeIsIdempotent() {
        let fakeRaw = 0x11223344
        _ = kk_freeze_object(fakeRaw)
        _ = kk_freeze_object(fakeRaw)
        XCTAssertEqual(kk_is_frozen(fakeRaw), 1, "Repeated freeze must still report frozen")
    }

    func testFreezeZeroObjectIsNoOp() {
        // Freezing 0 (null) must not crash and must leave isFrozen(0) == false.
        _ = kk_freeze_object(0)
        XCTAssertEqual(kk_is_frozen(0), 0, "Null (0) object must never report as frozen")
    }
}

final class RuntimeNativeRefDebuggingTests: XCTestCase {

    // MARK: - kotlin.native.runtime.Debugging (assertion enable / disable)

    func testAssertionsEnabledReturnsBooleanValue() {
        let result = kk_assertions_enabled()
        XCTAssertTrue(result == 0 || result == 1, "kk_assertions_enabled must return 0 or 1")
    }

    func testSetAssertionsEnabledFalseDisablesAssertions() {
        let original = kk_assertions_enabled()
        defer { _ = kk_assertions_set_enabled(original) }

        _ = kk_assertions_set_enabled(0)
        XCTAssertEqual(kk_assertions_enabled(), 0)
    }

    func testSetAssertionsEnabledTrueEnablesAssertions() {
        let original = kk_assertions_enabled()
        defer { _ = kk_assertions_set_enabled(original) }

        _ = kk_assertions_set_enabled(1)
        XCTAssertEqual(kk_assertions_enabled(), 1)
    }

    func testAssertionsResetRestoresInitialState() {
        let initial = kk_assertions_enabled()
        // Flip to opposite.
        _ = kk_assertions_set_enabled(initial == 1 ? 0 : 1)
        // Reset must restore to the environment-driven initial state.
        _ = kk_assertions_reset()
        XCTAssertEqual(kk_assertions_enabled(), initial)
    }

    func testSetAssertionsEnabledReturnZero() {
        let rc = kk_assertions_set_enabled(1)
        XCTAssertEqual(rc, 0, "kk_assertions_set_enabled must return 0")
    }

    func testAssertionsResetReturnZero() {
        let rc = kk_assertions_reset()
        XCTAssertEqual(rc, 0, "kk_assertions_reset must return 0")
    }
}
