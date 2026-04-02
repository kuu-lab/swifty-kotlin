@testable import Runtime
import XCTest

final class RuntimeAtomicArrayTests: XCTestCase {
    private func runtimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self)
        else {
            return ""
        }
        return box.value
    }

    func testAtomicIntArrayBoxSupportsIndexedAtomicOperations() {
        let box = AtomicIntArrayBox(size: 3)

        XCTAssertEqual(box.size(), 3)
        XCTAssertEqual(box.get(index: 0, outThrown: nil), 0)
        XCTAssertEqual(box.set(index: 1, value: 7, outThrown: nil), 0)
        XCTAssertEqual(box.get(index: 1, outThrown: nil), 7)
        XCTAssertEqual(box.compareAndSet(index: 1, expect: 7, update: 9, outThrown: nil), 1)
        XCTAssertEqual(box.compareAndExchange(index: 1, expect: 9, update: 11, outThrown: nil), 9)
        XCTAssertEqual(box.fetchAndAdd(index: 1, delta: 2, outThrown: nil), 11)
        XCTAssertEqual(box.addAndFetch(index: 1, delta: 3, outThrown: nil), 16)
        XCTAssertEqual(box.fetchAndIncrement(index: 1, outThrown: nil), 16)
        XCTAssertEqual(box.incrementAndFetch(index: 1, outThrown: nil), 18)
        XCTAssertEqual(box.fetchAndDecrement(index: 1, outThrown: nil), 18)
        XCTAssertEqual(box.decrementAndFetch(index: 1, outThrown: nil), 16)
        XCTAssertEqual(box.toString(), "[0, 16, 0]")
    }

    func testAtomicIntArrayBoxReportsBoundsErrors() {
        let box = AtomicIntArrayBox(size: 1)
        var thrown = 0

        XCTAssertEqual(box.get(index: 2, outThrown: &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testAtomicIntArrayRuntimeEntrypoints() {
        let source = RuntimeArrayBox(length: 3)
        source.elements = [4, 5, 6]
        let sourceRaw = registerRuntimeObject(source)
        let arrayRaw = kk_atomic_int_array_createFromArray(sourceRaw)

        XCTAssertEqual(kk_atomic_int_array_size(arrayRaw), 3)

        var thrown = 0
        XCTAssertEqual(kk_atomic_int_array_get(arrayRaw, 0, &thrown), 4)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_int_array_set(arrayRaw, 1, 9, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_int_array_get(arrayRaw, 1, &thrown), 9)

        XCTAssertEqual(kk_atomic_int_array_compareAndSet(arrayRaw, 1, 9, 12, &thrown), 1)
        XCTAssertEqual(kk_atomic_int_array_compareAndExchange(arrayRaw, 1, 12, 15, &thrown), 12)
        XCTAssertEqual(kk_atomic_int_array_getAndAdd(arrayRaw, 2, 5, &thrown), 6)
        XCTAssertEqual(kk_atomic_int_array_addAndGet(arrayRaw, 2, 1, &thrown), 12)
        XCTAssertEqual(kk_atomic_int_array_getAndIncrement(arrayRaw, 2, &thrown), 12)
        XCTAssertEqual(kk_atomic_int_array_incrementAndGet(arrayRaw, 2, &thrown), 14)
        XCTAssertEqual(kk_atomic_int_array_getAndDecrement(arrayRaw, 2, &thrown), 14)
        XCTAssertEqual(kk_atomic_int_array_decrementAndGet(arrayRaw, 2, &thrown), 12)

        let toStringRaw = kk_atomic_int_array_toString(arrayRaw)
        XCTAssertEqual(runtimeString(toStringRaw), "[4, 15, 12]")
    }

    func testAtomicLongArrayBoxSupportsIndexedAtomicOperations() {
        let box = AtomicLongArrayBox(size: 3)

        XCTAssertEqual(box.size(), 3)
        XCTAssertEqual(box.get(index: 0, outThrown: nil), 0)
        XCTAssertEqual(box.set(index: 1, value: 7, outThrown: nil), 0)
        XCTAssertEqual(box.get(index: 1, outThrown: nil), 7)
        XCTAssertEqual(box.compareAndSet(index: 1, expect: 7, update: 9, outThrown: nil), 1)
        XCTAssertEqual(box.compareAndExchange(index: 1, expect: 9, update: 11, outThrown: nil), 9)
        XCTAssertEqual(box.fetchAndAdd(index: 1, delta: 2, outThrown: nil), 11)
        XCTAssertEqual(box.addAndFetch(index: 1, delta: 3, outThrown: nil), 16)
        XCTAssertEqual(box.fetchAndIncrement(index: 1, outThrown: nil), 16)
        XCTAssertEqual(box.incrementAndFetch(index: 1, outThrown: nil), 18)
        XCTAssertEqual(box.fetchAndDecrement(index: 1, outThrown: nil), 18)
        XCTAssertEqual(box.decrementAndFetch(index: 1, outThrown: nil), 16)
        XCTAssertEqual(box.toString(), "[0, 16, 0]")
    }

    func testAtomicLongArrayBoxReportsBoundsErrors() {
        let box = AtomicLongArrayBox(size: 1)
        var thrown = 0

        XCTAssertEqual(box.get(index: 2, outThrown: &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testAtomicLongArrayRuntimeEntrypoints() {
        let source = RuntimeArrayBox(length: 3)
        source.elements = [40, 50, 60]
        let sourceRaw = registerRuntimeObject(source)
        let arrayRaw = kk_atomic_long_array_createFromArray(sourceRaw)

        XCTAssertEqual(kk_atomic_long_array_size(arrayRaw), 3)

        var thrown = 0
        XCTAssertEqual(kk_atomic_long_array_get(arrayRaw, 0, &thrown), 40)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_atomic_long_array_set(arrayRaw, 1, 90, &thrown), 0)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_atomic_long_array_get(arrayRaw, 1, &thrown), 90)

        XCTAssertEqual(kk_atomic_long_array_compareAndSet(arrayRaw, 1, 90, 120, &thrown), 1)
        XCTAssertEqual(kk_atomic_long_array_compareAndExchange(arrayRaw, 1, 120, 150, &thrown), 120)
        XCTAssertEqual(kk_atomic_long_array_getAndAdd(arrayRaw, 2, 5, &thrown), 60)
        XCTAssertEqual(kk_atomic_long_array_addAndGet(arrayRaw, 2, 1, &thrown), 66)
        XCTAssertEqual(kk_atomic_long_array_getAndIncrement(arrayRaw, 2, &thrown), 66)
        XCTAssertEqual(kk_atomic_long_array_incrementAndGet(arrayRaw, 2, &thrown), 68)
        XCTAssertEqual(kk_atomic_long_array_getAndDecrement(arrayRaw, 2, &thrown), 68)
        XCTAssertEqual(kk_atomic_long_array_decrementAndGet(arrayRaw, 2, &thrown), 66)

        let toStringRaw = kk_atomic_long_array_toString(arrayRaw)
        XCTAssertEqual(runtimeString(toStringRaw), "[40, 150, 66]")
    }
}
