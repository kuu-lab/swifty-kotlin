import Foundation
#if canImport(Testing)
import Testing
@testable import Runtime

// MARK: - AtomicArray<T> runtime tests (STDLIB-033-ABI-002)
//
// Covers kk_atomic_ref_array_* cdecl entries introduced for the generic
// kotlin.concurrent.atomics.AtomicArray<T> class.
// CAS uses identity semantics (pointer equality), not structural equality.

private let refArrayThunkReturn42: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 42 }
private let refArrayThunkReturn42Ptr = unsafeBitCast(refArrayThunkReturn42, to: Int.self)

@Suite
struct RuntimeAtomicRefArrayTests {

    // MARK: - new / size

    @Test
    func testNewReturnsNonZeroHandle() {
        let handle = kk_atomic_ref_array_new(4)
        #expect(handle != 0)
    }

    @Test
    func testSizeMatchesRequestedCapacity() {
        let handle = kk_atomic_ref_array_new(7)
        #expect(kk_atomic_ref_array_size(handle) == 7)
    }

    @Test
    func testZeroSizeArrayIsAllowed() {
        let handle = kk_atomic_ref_array_new(0)
        #expect(handle != 0)
        #expect(kk_atomic_ref_array_size(handle) == 0)
    }

    @Test
    func testInvalidHandleSizeReturnsZero() {
        #expect(kk_atomic_ref_array_size(0) == 0)
    }

    // MARK: - loadAt / storeAt

    @Test
    func testInitialElementsAreZero() {
        let handle = kk_atomic_ref_array_new(3)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 1) == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 2) == 0)
    }

    @Test
    func testStoreAndLoadRoundTrip() {
        let handle = kk_atomic_ref_array_new(5)
        let ref = kk_atomic_int_create(42) // use a managed object pointer as the "reference"
        kk_atomic_ref_array_storeAt(handle, 2, ref)
        #expect(kk_atomic_ref_array_loadAt(handle, 2) == ref)
    }

    @Test
    func testStoreAtFirstAndLastIndex() {
        let handle = kk_atomic_ref_array_new(4)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        kk_atomic_ref_array_storeAt(handle, 0, refA)
        kk_atomic_ref_array_storeAt(handle, 3, refB)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == refA)
        #expect(kk_atomic_ref_array_loadAt(handle, 3) == refB)
    }

    @Test
    func testLoadAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(2)
        #expect(kk_atomic_ref_array_loadAt(handle, 5) == 0)
    }

    @Test
    func testStoreAtOutOfBoundsIsNoop() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(99)
        kk_atomic_ref_array_storeAt(handle, 10, ref)
        // No crash and indices within bounds remain zero
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 1) == 0)
    }

    @Test
    func testStoreReturnsZeroUnit() {
        let handle = kk_atomic_ref_array_new(1)
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_storeAt(handle, 0, ref)
        #expect(result == 0)
    }

    // MARK: - compareAndSetAt (identity-based)

    @Test
    func testCompareAndSetAtSucceedsWhenExpectMatches() {
        let handle = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        kk_atomic_ref_array_storeAt(handle, 1, refA)

        let result = kk_atomic_ref_array_compareAndSetAt(handle, 1, refA, refB)
        #expect(result == 1, "CAS must succeed (return 1) when expected identity matches")
        #expect(kk_atomic_ref_array_loadAt(handle, 1) == refB)
    }

    @Test
    func testCompareAndSetAtFailsWhenExpectMismatches() {
        let handle = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(10)
        let refB = kk_atomic_int_create(20)
        let refC = kk_atomic_int_create(30)
        kk_atomic_ref_array_storeAt(handle, 1, refA)

        let result = kk_atomic_ref_array_compareAndSetAt(handle, 1, refC, refB)
        #expect(result == 0, "CAS must fail (return 0) on identity mismatch")
        #expect(kk_atomic_ref_array_loadAt(handle, 1) == refA, "Value must not change on failure")
    }

    @Test
    func testCompareAndSetAtOutOfBoundsReturnsFalse() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_compareAndSetAt(handle, 99, 0, ref)
        #expect(result == 0)
    }

    @Test
    func testCompareAndSetAtIsIdempotentWhenAlreadyNew() {
        let handle = kk_atomic_ref_array_new(1)
        let ref = kk_atomic_int_create(7)
        kk_atomic_ref_array_storeAt(handle, 0, ref)

        // Successful CAS sets value to ref; subsequent CAS with old=ref and same new=ref succeeds
        let r1 = kk_atomic_ref_array_compareAndSetAt(handle, 0, ref, ref)
        #expect(r1 == 1)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == ref)
    }

    // MARK: - compareAndExchangeAt (identity-based)

    @Test
    func testCompareAndExchangeAtReturnsOldValueOnSuccess() {
        let handle = kk_atomic_ref_array_new(2)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        kk_atomic_ref_array_storeAt(handle, 0, refA)

        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 0, refA, refB)
        #expect(old == refA, "compareAndExchangeAt must return the old value on success")
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == refB)
    }

    @Test
    func testCompareAndExchangeAtReturnsCurrentValueOnFailure() {
        let handle = kk_atomic_ref_array_new(2)
        let refA = kk_atomic_int_create(1)
        let refB = kk_atomic_int_create(2)
        let refC = kk_atomic_int_create(3)
        kk_atomic_ref_array_storeAt(handle, 0, refA)

        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 0, refC, refB)
        #expect(old == refA, "compareAndExchangeAt must return current value on failure")
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == refA, "Value must not change on failure")
    }

    @Test
    func testCompareAndExchangeAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(2)
        let ref = kk_atomic_int_create(1)
        let old = kk_atomic_ref_array_compareAndExchangeAt(handle, 99, 0, ref)
        #expect(old == 0)
    }

    // MARK: - fetchAndUpdateAt

    @Test
    func testFetchAndUpdateAtReturnsOldValueAndStoresTransformedValue() {
        let handle = kk_atomic_ref_array_new(1)
        kk_atomic_ref_array_storeAt(handle, 0, 10)

        let old = kk_atomic_ref_array_fetchAndUpdateAt(handle, 0, refArrayThunkReturn42Ptr, nil)

        #expect(old == 10)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 42)
    }

    @Test
    func testFetchAndUpdateAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(1)

        let old = kk_atomic_ref_array_fetchAndUpdateAt(handle, 2, refArrayThunkReturn42Ptr, nil)

        #expect(old == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 0)
    }

    @Test
    func testUpdateAtStoresTransformedValueAndReturnsUnit() {
        let handle = kk_atomic_ref_array_new(1)
        kk_atomic_ref_array_storeAt(handle, 0, 10)

        let result = kk_atomic_ref_array_updateAt(handle, 0, refArrayThunkReturn42Ptr, nil)

        #expect(result == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 42)
    }

    @Test
    func testUpdateAndFetchAtReturnsNewValueAndStoresTransformedValue() {
        let handle = kk_atomic_ref_array_new(1)
        kk_atomic_ref_array_storeAt(handle, 0, 10)

        let new = kk_atomic_ref_array_updateAndFetchAt(handle, 0, refArrayThunkReturn42Ptr, nil)

        #expect(new == 42)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 42)
    }

    @Test
    func testUpdateAndFetchAtOutOfBoundsReturnsZero() {
        let handle = kk_atomic_ref_array_new(1)

        let new = kk_atomic_ref_array_updateAndFetchAt(handle, 2, refArrayThunkReturn42Ptr, nil)

        #expect(new == 0)
        #expect(kk_atomic_ref_array_loadAt(handle, 0) == 0)
    }

    // MARK: - Multiple independent arrays

    @Test
    func testTwoArraysDoNotInterfere() {
        let handleA = kk_atomic_ref_array_new(3)
        let handleB = kk_atomic_ref_array_new(3)
        let refA = kk_atomic_int_create(100)
        let refB = kk_atomic_int_create(200)

        kk_atomic_ref_array_storeAt(handleA, 0, refA)
        kk_atomic_ref_array_storeAt(handleB, 0, refB)

        #expect(kk_atomic_ref_array_loadAt(handleA, 0) == refA)
        #expect(kk_atomic_ref_array_loadAt(handleB, 0) == refB)
    }

    // MARK: - Invalid handle safety

    @Test
    func testInvalidHandleLoadAtReturnsZero() {
        #expect(kk_atomic_ref_array_loadAt(0, 0) == 0)
    }

    @Test
    func testInvalidHandleStoreAtIsNoop() {
        let ref = kk_atomic_int_create(1)
        let result = kk_atomic_ref_array_storeAt(0, 0, ref)
        #expect(result == 0)
    }

    @Test
    func testInvalidHandleCompareAndSetAtReturnsFalse() {
        let result = kk_atomic_ref_array_compareAndSetAt(0, 0, 0, 1)
        #expect(result == 0)
    }

    @Test
    func testInvalidHandleCompareAndExchangeAtReturnsZero() {
        let result = kk_atomic_ref_array_compareAndExchangeAt(0, 0, 0, 1)
        #expect(result == 0)
    }
}
#endif
