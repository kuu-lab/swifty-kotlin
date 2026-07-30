import Dispatch
import Foundation
@testable import Runtime
import XCTest

// MARK: - kotlin.native.concurrent extended runtime ABI coverage (STDLIB-NATIVE-CONCURRENT-003)
//
// This file adds extended runtime coverage not addressed by
// RuntimeNativeConcurrentTests.swift, which covers Worker lifecycle,
// freeze/isFrozen, Worker.id, Future<T>, TransferMode, FreezableAtomicReference,
// @SharedImmutable, Worker.executeAfter, and basic AtomicInt/Long/Reference CAS.
//
// Implemented APIs tested here:
//   AtomicBoolean  : kk_atomic_bool_create / load / store / exchange /
//                    compareAndSet / compareAndExchange
//   AtomicIntArray : kk_atomic_int_array_create / size / loadAt / storeAt /
//                    exchangeAt / compareAndSetAt / compareAndExchangeAt /
//                    fetchAndAddAt / addAndFetchAt / fetchAndIncrementAt /
//                    incrementAndFetchAt / fetchAndDecrementAt /
//                    decrementAndFetchAt
//   AtomicLongArray: kk_atomic_long_array_* (same shape as AtomicIntArray)
//   CPointer       : kk_cpointer_new / kk_cpointer_address
//   COpaquePointer : kk_copaque_pointer_new / kk_copaque_pointer_address
//   Pinned<T>      : kk_pin_object / kk_unpin_object / kk_pinned_get
//   @CName         : kk_cname_register / kk_cname_lookup
//
// Minimal native concurrent runtime ABI is implemented by RuntimeNativeAPI.swift,
// RuntimeNativeConcurrentABI.swift, RuntimeAtomic.swift, and RuntimeThreadLocal.swift.

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean
// ---------------------------------------------------------------------------

final class RuntimeAtomicBooleanTests: XCTestCase {

    func testCreateAndLoad() {
        let trueHandle = kk_atomic_bool_create(1)
        XCTAssertNotEqual(trueHandle, 0)
        XCTAssertEqual(kk_atomic_bool_load(trueHandle), 1)

        let falseHandle = kk_atomic_bool_create(0)
        XCTAssertNotEqual(falseHandle, 0)
        XCTAssertEqual(kk_atomic_bool_load(falseHandle), 0)
    }

    func testStore() {
        let handle = kk_atomic_bool_create(0)
        _ = kk_atomic_bool_store(handle, 1)
        XCTAssertEqual(kk_atomic_bool_load(handle), 1)
        _ = kk_atomic_bool_store(handle, 0)
        XCTAssertEqual(kk_atomic_bool_load(handle), 0)
    }

    func testExchange() {
        let handle = kk_atomic_bool_create(1)
        let old = kk_atomic_bool_exchange(handle, 0)
        XCTAssertEqual(old, 1, "exchange must return old value")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "exchange must store new value")
    }

    func testCompareAndSetSuccess() {
        let handle = kk_atomic_bool_create(0)
        let result = kk_atomic_bool_compareAndSet(handle, 0, 1)
        XCTAssertEqual(result, 1, "CAS must succeed (return 1) when expect matches")
        XCTAssertEqual(kk_atomic_bool_load(handle), 1)
    }

    func testCompareAndSetFailure() {
        let handle = kk_atomic_bool_create(0)
        let result = kk_atomic_bool_compareAndSet(handle, 1, 1)
        XCTAssertEqual(result, 0, "CAS must fail (return 0) when expect does not match")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "Value must not change on failed CAS")
    }

    func testCompareAndExchangeSuccess() {
        let handle = kk_atomic_bool_create(1)
        let old = kk_atomic_bool_compareAndExchange(handle, 1, 0)
        XCTAssertEqual(old, 1, "compareAndExchange must return old value on success")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0)
    }

    func testCompareAndExchangeFailure() {
        let handle = kk_atomic_bool_create(0)
        let old = kk_atomic_bool_compareAndExchange(handle, 1, 1)
        XCTAssertEqual(old, 0, "compareAndExchange must return current value on failure")
        XCTAssertEqual(kk_atomic_bool_load(handle), 0, "Value must not change on failure")
    }

    func testInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_atomic_bool_load(0), 0)
        XCTAssertEqual(kk_atomic_bool_store(0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_exchange(0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_compareAndSet(0, 0, 1), 0)
        XCTAssertEqual(kk_atomic_bool_compareAndExchange(0, 0, 1), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicIntArray
// ---------------------------------------------------------------------------

final class RuntimeAtomicIntArrayTests: XCTestCase {

    func testCreateAndSize() {
        let handle = kk_atomic_int_array_create(5)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_atomic_int_array_size(handle), 5)
    }

    // KSP-672: the public `*At` boundary layer and bounds checks now live in
    // Kotlin (Stdlib/kotlin/concurrent/AtomicArrayMigration.kt). These runtime
    // tests exercise only the raw synchronized-core `__kk_*` bridges, which
    // assume a pre-validated in-range index.

    func testInitialValuesAreZero() {
        let handle = kk_atomic_int_array_create(3)
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 0), 0)
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 1), 0)
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 2), 0)
    }

    func testStoreAndLoad() {
        let handle = kk_atomic_int_array_create(4)
        _ = __kk_atomic_int_array_store(handle, 2, 42)
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 2), 42)
    }

    func testExchange() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 0, 10)
        let old = __kk_atomic_int_array_exchange(handle, 0, 99)
        XCTAssertEqual(old, 10, "exchange must return the old value")
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 0), 99)
    }

    func testCompareAndExchangeSuccess() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 1, 7)
        let old = __kk_atomic_int_array_compareAndExchange(handle, 1, 7, 77)
        XCTAssertEqual(old, 7, "compareAndExchange returns the observed value")
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 1), 77)
    }

    func testCompareAndExchangeFailure() {
        let handle = kk_atomic_int_array_create(2)
        _ = __kk_atomic_int_array_store(handle, 0, 5)
        let old = __kk_atomic_int_array_compareAndExchange(handle, 0, 999, 50)
        XCTAssertEqual(old, 5, "compareAndExchange returns the current value on mismatch")
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 0), 5, "Value must not change on failed CAS")
    }

    func testFetchAndAdd() {
        let handle = kk_atomic_int_array_create(1)
        _ = __kk_atomic_int_array_store(handle, 0, 100)
        let old = __kk_atomic_int_array_fetchAndAdd(handle, 0, 5)
        XCTAssertEqual(old, 100)
        XCTAssertEqual(__kk_atomic_int_array_load(handle, 0), 105)
    }

    func testAddAndFetch() {
        let handle = kk_atomic_int_array_create(1)
        _ = __kk_atomic_int_array_store(handle, 0, 50)
        let new = __kk_atomic_int_array_addAndFetch(handle, 0, 10)
        XCTAssertEqual(new, 60)
    }

    func testZeroSizeArrayHasZeroSize() {
        let handle = kk_atomic_int_array_create(0)
        XCTAssertEqual(kk_atomic_int_array_size(handle), 0)
    }

    func testInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_atomic_int_array_size(0), 0)
        XCTAssertEqual(__kk_atomic_int_array_load(0, 0), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicLongArray
// ---------------------------------------------------------------------------

final class RuntimeAtomicLongArrayTests: XCTestCase {

    func testCreateAndSize() {
        let handle = kk_atomic_long_array_create(4)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_atomic_long_array_size(handle), 4)
    }

    // KSP-672: bounds checks and the public `*At` layer live in Kotlin; these
    // tests cover only the raw synchronized-core `__kk_*` bridges.

    func testStoreAndLoad() {
        let handle = kk_atomic_long_array_create(2)
        _ = __kk_atomic_long_array_store(handle, 0, 1000)
        XCTAssertEqual(__kk_atomic_long_array_load(handle, 0), 1000)
    }

    func testExchange() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 42)
        let old = __kk_atomic_long_array_exchange(handle, 0, 84)
        XCTAssertEqual(old, 42)
        XCTAssertEqual(__kk_atomic_long_array_load(handle, 0), 84)
    }

    func testCompareAndExchangeSuccess() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 99)
        XCTAssertEqual(__kk_atomic_long_array_compareAndExchange(handle, 0, 99, 199), 99)
        XCTAssertEqual(__kk_atomic_long_array_load(handle, 0), 199)
    }

    func testCompareAndExchangeFailure() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 10)
        XCTAssertEqual(__kk_atomic_long_array_compareAndExchange(handle, 0, 999, 20), 10)
        XCTAssertEqual(__kk_atomic_long_array_load(handle, 0), 10)
    }

    func testFetchAndAdd() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 500)
        let old = __kk_atomic_long_array_fetchAndAdd(handle, 0, 100)
        XCTAssertEqual(old, 500)
        XCTAssertEqual(__kk_atomic_long_array_load(handle, 0), 600)
    }

    func testAddAndFetch() {
        let handle = kk_atomic_long_array_create(1)
        _ = __kk_atomic_long_array_store(handle, 0, 50)
        let new = __kk_atomic_long_array_addAndFetch(handle, 0, 10)
        XCTAssertEqual(new, 60)
    }
}

// ---------------------------------------------------------------------------
// MARK: - CPointer / COpaquePointer
// ---------------------------------------------------------------------------

final class RuntimeCPointerTests: XCTestCase {

    func testCPointerRoundTrip() {
        let address = 0xDEAD_BEEF
        let handle = kk_cpointer_new(address)
        XCTAssertNotEqual(handle, 0)
        let recovered = kk_cpointer_address(handle)
        XCTAssertEqual(recovered, address)
    }

    func testCPointerZeroAddress() {
        let handle = kk_cpointer_new(0)
        XCTAssertNotEqual(handle, 0)
        XCTAssertEqual(kk_cpointer_address(handle), 0)
    }

    func testCPointerInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_cpointer_address(0), 0)
    }

    func testCOpaquePointerRoundTrip() {
        let address = 0x1234_5678
        let handle = kk_copaque_pointer_new(address)
        XCTAssertNotEqual(handle, 0)
        let recovered = kk_copaque_pointer_address(handle)
        XCTAssertEqual(recovered, address)
    }

    func testCOpaquePointerInvalidHandleReturnsZero() {
        XCTAssertEqual(kk_copaque_pointer_address(0), 0)
    }

    func testCPointerAndCOpaquePointerAreDistinct() {
        let address = 0xABCD
        let cptrHandle = kk_cpointer_new(address)
        let copaqueHandle = kk_copaque_pointer_new(address)
        // Each allocation produces a distinct handle.
        XCTAssertNotEqual(cptrHandle, copaqueHandle)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Pinned<T>
// ---------------------------------------------------------------------------

final class RuntimePinnedTests: XCTestCase {

    func testPinObjectReturnsNonZeroHandle() {
        let obj = kk_atomic_int_create(1)
        let pinHandle = kk_pin_object(obj)
        XCTAssertNotEqual(pinHandle, 0)
    }

    func testPinnedGetReturnsOriginalObject() {
        let obj = kk_atomic_int_create(2)
        let pinHandle = kk_pin_object(obj)
        XCTAssertEqual(kk_pinned_get(pinHandle), obj)
    }

    func testUnpinReturnsOriginalObject() {
        let obj = kk_atomic_int_create(3)
        let pinHandle = kk_pin_object(obj)
        let recovered = kk_unpin_object(pinHandle)
        XCTAssertEqual(recovered, obj)
    }

    func testPinZeroHandleReturnsZero() {
        XCTAssertEqual(kk_pin_object(0), 0)
    }

    func testPinnedGetOnZeroHandleReturnsZero() {
        XCTAssertEqual(kk_pinned_get(0), 0)
    }

    func testUnpinZeroHandleReturnsZero() {
        XCTAssertEqual(kk_unpin_object(0), 0)
    }

    func testPinDoesNotAlterOriginalAtomicValue() {
        let handle = kk_atomic_int_create(42)
        let pinHandle = kk_pin_object(handle)
        // The AtomicInt backing value must be unaffected by pinning.
        XCTAssertEqual(kk_atomic_int_load(handle), 42)
        _ = kk_unpin_object(pinHandle)
        XCTAssertEqual(kk_atomic_int_load(handle), 42)
    }
}

// ---------------------------------------------------------------------------
// MARK: - @CName registry
// ---------------------------------------------------------------------------

final class RuntimeCNameRegistryTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }

    func testRegisterAndLookupRoundTrip() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let fakePtr = 0x1_0000
        _ = kk_cname_register(nameHandle, fakePtr)

        let lookupNameHandle = registerRuntimeObject(RuntimeStringBox("myExportedFn"))
        let found = kk_cname_lookup(lookupNameHandle)
        XCTAssertEqual(found, fakePtr)
    }

    func testLookupMissingNameReturnsZero() {
        let nameHandle = registerRuntimeObject(RuntimeStringBox("doesNotExist"))
        XCTAssertEqual(kk_cname_lookup(nameHandle), 0)
    }

    func testRegisterOverwritesExistingEntry() {
        let nameHandle1 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle1, 0xAAAA)

        let nameHandle2 = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        _ = kk_cname_register(nameHandle2, 0xBBBB)

        let lookupHandle = registerRuntimeObject(RuntimeStringBox("duplicateName"))
        XCTAssertEqual(kk_cname_lookup(lookupHandle), 0xBBBB)
    }

    func testRegisterWithInvalidNameHandleIsNoOp() {
        // Passing 0 as name handle must not crash and must not register anything.
        _ = kk_cname_register(0, 0x1234)
        XCTAssertEqual(kk_cname_lookup(0), 0)
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicInt thread-safety smoke test
// ---------------------------------------------------------------------------

final class RuntimeAtomicIntConcurrencyTests: XCTestCase {

    func testConcurrentIncrementWithFetchAndAdd() {
        let handle = kk_atomic_int_create(0)
        let iterations = 1000
        let queueCount = 4
        let group = DispatchGroup()

        for _ in 0..<queueCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<iterations {
                    _ = kk_atomic_int_fetchAndAdd(handle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success, "Concurrent increment timed out")
        XCTAssertEqual(kk_atomic_int_load(handle), queueCount * iterations,
                       "Each increment must be atomic — no lost updates")
    }

    func testConcurrentCompareAndSetExactlyOneSucceeds() {
        // Many threads race to CAS from 0 -> 1; exactly one should win.
        // Use a separate AtomicInt runtime handle as win counter so we
        // avoid Sendable issues with AtomicIntBox directly.
        let handle = kk_atomic_int_create(0)
        let winCountHandle = kk_atomic_int_create(0)

        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let result = kk_atomic_int_compareAndSet(handle, 0, 1)
                if result == 1 {
                    _ = kk_atomic_int_fetchAndAdd(winCountHandle, 1)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success)
        XCTAssertEqual(kk_atomic_int_load(winCountHandle), 1,
                       "Exactly one CAS must win when racing from 0 -> 1")
    }
}

// ---------------------------------------------------------------------------
// MARK: - AtomicBoolean concurrency smoke test
// ---------------------------------------------------------------------------

final class RuntimeAtomicBoolConcurrencyTests: XCTestCase {

    func testConcurrentStoreAndLoadNeverCrashes() {
        let handle = kk_atomic_bool_create(0)
        let group = DispatchGroup()
        for i in 0..<4 {
            let val = i % 2
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<500 {
                    _ = kk_atomic_bool_store(handle, val)
                    _ = kk_atomic_bool_load(handle)
                }
                group.leave()
            }
        }
        let waitResult = group.wait(timeout: .now() + .seconds(10))
        XCTAssertEqual(waitResult, .success, "Concurrent bool store/load timed out or crashed")
    }
}
