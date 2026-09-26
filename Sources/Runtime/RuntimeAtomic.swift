import Foundation
import RuntimeCAtomics

// MARK: - AtomicInt

/// Backing storage for kotlin.concurrent.AtomicInt.
/// A single seq-cst hardware atomic cell instead of a mutex per box.
final class AtomicIntBox {
    private let storage: UnsafeMutablePointer<Int32>

    init(initial: Int) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: atomicInt32Value(initial))
    }

    deinit {
        storage.deallocate()
    }

    func load() -> Int {
        Int(kkrt_atomic_i32_load(storage))
    }

    func store(_ value: Int) {
        kkrt_atomic_i32_store(storage, atomicInt32Value(value))
    }

    func exchange(_ new: Int) -> Int {
        Int(kkrt_atomic_i32_exchange(storage, atomicInt32Value(new)))
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        var exchanged = false
        kkrt_atomic_i32_compare_exchange(
            storage, atomicInt32Value(expect), atomicInt32Value(update), &exchanged
        )
        return exchanged
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        var exchanged = false
        let old = kkrt_atomic_i32_compare_exchange(
            storage, atomicInt32Value(expect), atomicInt32Value(update), &exchanged
        )
        return Int(old)
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        Int(kkrt_atomic_i32_fetch_add(storage, atomicInt32Value(delta)))
    }

    func addAndFetch(_ delta: Int) -> Int {
        let delta32 = atomicInt32Value(delta)
        let old = kkrt_atomic_i32_fetch_add(storage, delta32)
        return Int(old &+ delta32)
    }
}

/// Kotlin `Int` arithmetic and storage are defined over signed 32-bit values.
private func atomicInt32Value(_ value: Int) -> Int32 {
    Int32(truncatingIfNeeded: value)
}

private func atomicIntBox(from raw: Int) -> AtomicIntBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicIntBox.self)
}

@_cdecl("kk_atomic_int_create")
public func kk_atomic_int_create(_ initial: Int) -> Int {
    let box = AtomicIntBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_int_load")
public func __kk_atomic_int_load(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_int_store")
public func __kk_atomic_int_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_int_exchange")
public func __kk_atomic_int_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_int_compareAndSet")
public func kk_atomic_int_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("__kk_atomic_int_compareAndExchange")
public func __kk_atomic_int_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("__kk_atomic_int_fetchAndAdd")
public func __kk_atomic_int_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("__kk_atomic_int_addAndFetch")
public func __kk_atomic_int_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("__kk_atomic_int_fetchAndIncrement")
public func __kk_atomic_int_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("__kk_atomic_int_fetchAndDecrement")
public func __kk_atomic_int_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("__kk_atomic_int_incrementAndFetch")
public func __kk_atomic_int_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("__kk_atomic_int_decrementAndFetch")
public func __kk_atomic_int_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

// MARK: - AtomicLong

/// Backing storage for kotlin.concurrent.AtomicLong.
final class AtomicLongBox {
    private let storage: UnsafeMutablePointer<Int>

    init(initial: Int) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: initial)
    }

    deinit {
        storage.deallocate()
    }

    func load() -> Int {
        kkrt_atomic_word_load(storage)
    }

    func store(_ value: Int) {
        kkrt_atomic_word_store(storage, value)
    }

    func exchange(_ new: Int) -> Int {
        kkrt_atomic_word_exchange(storage, new)
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        var exchanged = false
        kkrt_atomic_word_compare_exchange(storage, expect, update, &exchanged)
        return exchanged
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        var exchanged = false
        return kkrt_atomic_word_compare_exchange(storage, expect, update, &exchanged)
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        kkrt_atomic_word_fetch_add(storage, delta)
    }

    func addAndFetch(_ delta: Int) -> Int {
        let old = kkrt_atomic_word_fetch_add(storage, delta)
        return old &+ delta
    }
}

private func atomicLongBox(from raw: Int) -> AtomicLongBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicLongBox.self)
}

@_cdecl("kk_atomic_long_create")
public func kk_atomic_long_create(_ initial: Int) -> Int {
    let box = AtomicLongBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_long_load")
public func __kk_atomic_long_load(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_long_store")
public func __kk_atomic_long_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_long_exchange")
public func __kk_atomic_long_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_long_compareAndSet")
public func kk_atomic_long_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("__kk_atomic_long_compareAndExchange")
public func __kk_atomic_long_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("__kk_atomic_long_fetchAndAdd")
public func __kk_atomic_long_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("__kk_atomic_long_addAndFetch")
public func __kk_atomic_long_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("__kk_atomic_long_fetchAndIncrement")
public func __kk_atomic_long_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("__kk_atomic_long_fetchAndDecrement")
public func __kk_atomic_long_fetchAndDecrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(-1)
}

@_cdecl("__kk_atomic_long_incrementAndFetch")
public func __kk_atomic_long_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("__kk_atomic_long_decrementAndFetch")
public func __kk_atomic_long_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

// MARK: - AtomicBoolean

/// Backing storage for kotlin.concurrent.AtomicBoolean.
/// Boolean values are stored as Int: 1 = true, 0 = false.
final class AtomicBooleanBox {
    private let storage: UnsafeMutablePointer<Int>

    init(initial: Bool) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: initial ? 1 : 0)
    }

    deinit {
        storage.deallocate()
    }

    func load() -> Bool {
        kkrt_atomic_word_load(storage) != 0
    }

    func store(_ value: Bool) {
        kkrt_atomic_word_store(storage, value ? 1 : 0)
    }

    func exchange(_ new: Bool) -> Bool {
        kkrt_atomic_word_exchange(storage, new ? 1 : 0) != 0
    }

    func compareAndExchange(expect: Bool, update: Bool) -> Bool {
        var exchanged = false
        let old = kkrt_atomic_word_compare_exchange(
            storage, expect ? 1 : 0, update ? 1 : 0, &exchanged
        )
        return old != 0
    }
}

private func atomicBoolBox(from raw: Int) -> AtomicBooleanBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicBooleanBox.self)
}

@_cdecl("kk_atomic_bool_create")
public func kk_atomic_bool_create(_ initial: Int) -> Int {
    let box = AtomicBooleanBox(initial: initial != 0)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_bool_load")
public func __kk_atomic_bool_load(_ receiver: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.load() ? 1 : 0
}

@_cdecl("__kk_atomic_bool_store")
public func __kk_atomic_bool_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    box.store(value != 0)
    return 0
}

@_cdecl("__kk_atomic_bool_exchange")
public func __kk_atomic_bool_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.exchange(new != 0) ? 1 : 0
}

@_cdecl("__kk_atomic_bool_compareAndExchange")
public func __kk_atomic_bool_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect != 0, update: update != 0) ? 1 : 0
}

// MARK: - AtomicReference<T>

/// Backing storage for kotlin.concurrent.AtomicReference<T>.
/// Values are stored as opaque intptr_t (object pointers or boxed values).
final class AtomicRefBox {
    private let storage: UnsafeMutablePointer<Int>

    init(initial: Int) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: initial)
    }

    deinit {
        storage.deallocate()
    }

    func load() -> Int {
        kkrt_atomic_word_load(storage)
    }

    func store(_ value: Int) {
        kkrt_atomic_word_store(storage, value)
    }

    func exchange(_ new: Int) -> Int {
        kkrt_atomic_word_exchange(storage, new)
    }

    /// Kotlin `AtomicReference` CAS uses reference identity, so raw handles
    /// are compared rather than their structural values.
    func compareAndExchange(expect: Int, update: Int) -> Int {
        var exchanged = false
        return kkrt_atomic_word_compare_exchange(storage, expect, update, &exchanged)
    }
}

private func atomicRefBox(from raw: Int) -> AtomicRefBox? {
    guard raw != 0, raw != runtimeNullSentinelInt, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: AtomicRefBox.self)
}

@_cdecl("kk_atomic_ref_create")
public func kk_atomic_ref_create(_ initial: Int) -> Int {
    let box = AtomicRefBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_atomic_ref_load")
public func __kk_atomic_ref_load(_ receiver: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("__kk_atomic_ref_store")
public func __kk_atomic_ref_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("__kk_atomic_ref_exchange")
public func __kk_atomic_ref_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("__kk_atomic_ref_compareAndExchange")
public func __kk_atomic_ref_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

// MARK: - AtomicIntArray

/// Backing storage for kotlin.concurrent.atomics.AtomicIntArray.
/// Each element is an independent seq-cst atomic cell, so operations on
/// distinct indices don't contend on a shared lock.
final class AtomicIntArrayBox {
    private let storage: UnsafeMutableBufferPointer<Int32>

    init(size: Int) {
        storage = .allocate(capacity: max(0, size))
        storage.initialize(repeating: 0)
    }

    deinit {
        storage.deallocate()
    }

    func size() -> Int {
        storage.count
    }

    private func cell(at index: Int) -> UnsafeMutablePointer<Int32>? {
        guard index >= 0, index < storage.count else { return nil }
        return storage.baseAddress?.advanced(by: index)
    }

    func load(at index: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return Int(kkrt_atomic_i32_load(cell))
    }

    func store(at index: Int, value: Int) {
        guard let cell = cell(at: index) else { return }
        kkrt_atomic_i32_store(cell, atomicInt32Value(value))
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return Int(kkrt_atomic_i32_exchange(cell, atomicInt32Value(newValue)))
    }

    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        guard let cell = cell(at: index) else { return false }
        var exchanged = false
        kkrt_atomic_i32_compare_exchange(
            cell, atomicInt32Value(expect), atomicInt32Value(update), &exchanged
        )
        return exchanged
    }

    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        var exchanged = false
        let old = kkrt_atomic_i32_compare_exchange(
            cell, atomicInt32Value(expect), atomicInt32Value(update), &exchanged
        )
        return Int(old)
    }

    func fetchAndAdd(at index: Int, delta: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return Int(kkrt_atomic_i32_fetch_add(cell, atomicInt32Value(delta)))
    }

    func addAndFetch(at index: Int, delta: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        let delta32 = atomicInt32Value(delta)
        let old = kkrt_atomic_i32_fetch_add(cell, delta32)
        return Int(old &+ delta32)
    }
}

private func atomicIntArrayBox(from raw: Int) -> AtomicIntArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicIntArrayBox.self)
}

// (a) RF-DEAD-002: 配線予定 → MIGRATION-ATOMIC-001 (AtomicIntArray / AtomicLongArray サポート)
@_cdecl("kk_atomic_int_array_create")
public func kk_atomic_int_array_create(_ size: Int) -> Int {
    let box = AtomicIntArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_int_array_size")
public func kk_atomic_int_array_size(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.size()
}

// KSP-672: The public `*At` boundary layer and bounds checks now live in Kotlin
// (Stdlib/kotlin/concurrent/AtomicArrayMigration.kt). These `__kk_*` bridges are
// the raw synchronized core: they assume the index has already been validated by
// the Kotlin caller and never allocate exceptions.
@_cdecl("__kk_atomic_int_array_load")
public func __kk_atomic_int_array_load(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@_cdecl("__kk_atomic_int_array_store")
public func __kk_atomic_int_array_store(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("__kk_atomic_int_array_exchange")
public func __kk_atomic_int_array_exchange(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("__kk_atomic_int_array_compareAndExchange")
public func __kk_atomic_int_array_compareAndExchange(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int
) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("__kk_atomic_int_array_fetchAndAdd")
public func __kk_atomic_int_array_fetchAndAdd(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("__kk_atomic_int_array_addAndFetch")
public func __kk_atomic_int_array_addAndFetch(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(at: index, delta: delta)
}

// MARK: - AtomicLongArray

/// Backing storage for kotlin.concurrent.atomics.AtomicLongArray.
final class AtomicLongArrayBox {
    private let storage: UnsafeMutableBufferPointer<Int>

    init(size: Int) {
        storage = .allocate(capacity: max(0, size))
        storage.initialize(repeating: 0)
    }

    deinit {
        storage.deallocate()
    }

    func size() -> Int {
        storage.count
    }

    private func cell(at index: Int) -> UnsafeMutablePointer<Int>? {
        guard index >= 0, index < storage.count else { return nil }
        return storage.baseAddress?.advanced(by: index)
    }

    func load(at index: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return kkrt_atomic_word_load(cell)
    }

    func store(at index: Int, value: Int) {
        guard let cell = cell(at: index) else { return }
        kkrt_atomic_word_store(cell, value)
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return kkrt_atomic_word_exchange(cell, newValue)
    }

    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        guard let cell = cell(at: index) else { return false }
        var exchanged = false
        kkrt_atomic_word_compare_exchange(cell, expect, update, &exchanged)
        return exchanged
    }

    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        var exchanged = false
        return kkrt_atomic_word_compare_exchange(cell, expect, update, &exchanged)
    }

    func fetchAndAdd(at index: Int, delta: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return kkrt_atomic_word_fetch_add(cell, delta)
    }

    func addAndFetch(at index: Int, delta: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        let old = kkrt_atomic_word_fetch_add(cell, delta)
        return old &+ delta
    }
}

private func atomicLongArrayBox(from raw: Int) -> AtomicLongArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return tryCast(ptr, to: AtomicLongArrayBox.self)
}

@_cdecl("kk_atomic_long_array_create")
public func kk_atomic_long_array_create(_ size: Int) -> Int {
    let box = AtomicLongArrayBox(size: size)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_array_size")
public func kk_atomic_long_array_size(_ receiver: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.size()
}

// KSP-672: Raw synchronized core for AtomicLongArray. Bounds checks and the
// public `*At` layer live in Kotlin (AtomicArrayMigration.kt); these bridges
// assume a pre-validated index and never allocate exceptions.
@_cdecl("__kk_atomic_long_array_load")
public func __kk_atomic_long_array_load(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@_cdecl("__kk_atomic_long_array_store")
public func __kk_atomic_long_array_store(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("__kk_atomic_long_array_exchange")
public func __kk_atomic_long_array_exchange(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("__kk_atomic_long_array_compareAndExchange")
public func __kk_atomic_long_array_compareAndExchange(
    _ receiver: Int, _ index: Int, _ expect: Int, _ update: Int
) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}

@_cdecl("__kk_atomic_long_array_fetchAndAdd")
public func __kk_atomic_long_array_fetchAndAdd(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(at: index, delta: delta)
}

@_cdecl("__kk_atomic_long_array_addAndFetch")
public func __kk_atomic_long_array_addAndFetch(_ receiver: Int, _ index: Int, _ delta: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(at: index, delta: delta)
}

// MARK: - AtomicArray<T> (generic reference-typed array)

/// Backing storage for kotlin.concurrent.atomics.AtomicArray<T>.
/// Elements are stored as opaque intptr_t (object pointers or boxed values).
/// CAS uses identity semantics: two values compare equal iff their raw Int
/// representation is identical (i.e. pointer identity, not structural equality).
final class AtomicRefArrayBox {
    private let storage: UnsafeMutableBufferPointer<Int>

    init(size: Int) {
        storage = .allocate(capacity: max(0, size))
        storage.initialize(repeating: 0)
    }

    deinit {
        storage.deallocate()
    }

    func size() -> Int {
        storage.count
    }

    private func cell(at index: Int) -> UnsafeMutablePointer<Int>? {
        guard index >= 0, index < storage.count else { return nil }
        return storage.baseAddress?.advanced(by: index)
    }

    func load(at index: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return kkrt_atomic_word_load(cell)
    }

    func store(at index: Int, value: Int) {
        guard let cell = cell(at: index) else { return }
        kkrt_atomic_word_store(cell, value)
    }

    func exchange(at index: Int, newValue: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        return kkrt_atomic_word_exchange(cell, newValue)
    }

    /// Identity-based CAS, with string boxes compared structurally because aggregate
    /// string lowering may materialize an equivalent RuntimeStringBox at ABI edges.
    /// The CAS loop retries on the newly observed value so the swap still happens
    /// iff the cell held a matching value at the successful compare-exchange.
    func compareAndSet(at index: Int, expect: Int, update: Int) -> Bool {
        guard let cell = cell(at: index) else { return false }
        var observed = kkrt_atomic_word_load(cell)
        while runtimeAtomicRefValuesMatch(observed, expect) {
            var exchanged = false
            observed = kkrt_atomic_word_compare_exchange(cell, observed, update, &exchanged)
            if exchanged { return true }
        }
        return false
    }

    /// Identity-based compareAndExchange: returns the previous value regardless of success.
    func compareAndExchange(at index: Int, expect: Int, update: Int) -> Int {
        guard let cell = cell(at: index) else { return 0 }
        var observed = kkrt_atomic_word_load(cell)
        while runtimeAtomicRefValuesMatch(observed, expect) {
            var exchanged = false
            observed = kkrt_atomic_word_compare_exchange(cell, observed, update, &exchanged)
            if exchanged { break }
        }
        return observed
    }
}

private func atomicRefArrayBox(from raw: Int) -> AtomicRefArrayBox? {
    guard raw != 0, raw != runtimeNullSentinelInt, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: AtomicRefArrayBox.self)
}

private func registerAtomicRefArrayBox(_ box: AtomicRefArrayBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeAtomicRefValuesMatch(_ lhs: Int, _ rhs: Int) -> Bool {
    if lhs == rhs {
        return true
    }
    let lhsIsNull = (lhs == 0 || lhs == runtimeNullSentinelInt)
    let rhsIsNull = (rhs == 0 || rhs == runtimeNullSentinelInt)
    if lhsIsNull || rhsIsNull {
        return lhsIsNull && rhsIsNull
    }
    guard
        let lhsPointer = UnsafeMutableRawPointer(bitPattern: lhs),
        let rhsPointer = UnsafeMutableRawPointer(bitPattern: rhs)
    else {
        return false
    }
    let (lhsRegistered, rhsRegistered) = runtimeStorage.withGCLock { state in
        (
            state.objectPointers.contains(UInt(bitPattern: lhsPointer)),
            state.objectPointers.contains(UInt(bitPattern: rhsPointer))
        )
    }
    guard lhsRegistered, rhsRegistered else {
        return false
    }
    guard
        let lhsString = tryCast(lhsPointer, to: RuntimeStringBox.self),
        let rhsString = tryCast(rhsPointer, to: RuntimeStringBox.self)
    else {
        return false
    }
    return runtimeStringsEqual(lhsString.value, rhsString.value)
}

@_cdecl("kk_atomic_ref_array_new")
public func kk_atomic_ref_array_new(_ size: Int) -> Int {
    let box = AtomicRefArrayBox(size: size)
    return registerAtomicRefArrayBox(box)
}

@_cdecl("kk_atomic_ref_array_of")
public func kk_atomic_ref_array_of(_ arrayRaw: Int) -> Int {
    let elements = runtimeArrayBox(from: arrayRaw)?.elements ?? []
    let box = AtomicRefArrayBox(size: elements.count)
    for (index, element) in elements.enumerated() {
        box.store(at: index, value: element)
    }
    return registerAtomicRefArrayBox(box)
}

@_cdecl("kk_atomic_ref_array_size")
public func kk_atomic_ref_array_size(_ receiver: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_ref_array_loadAt")
public func kk_atomic_ref_array_loadAt(_ receiver: Int, _ index: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.load(at: index)
}

@discardableResult
@_cdecl("kk_atomic_ref_array_storeAt")
public func kk_atomic_ref_array_storeAt(_ receiver: Int, _ index: Int, _ value: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    box.store(at: index, value: value)
    return 0
}

@_cdecl("kk_atomic_ref_array_exchangeAt")
public func kk_atomic_ref_array_exchangeAt(_ receiver: Int, _ index: Int, _ newValue: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.exchange(at: index, newValue: newValue)
}

@_cdecl("kk_atomic_ref_array_compareAndSetAt")
public func kk_atomic_ref_array_compareAndSetAt(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.compareAndSet(at: index, expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_ref_array_compareAndExchangeAt")
public func kk_atomic_ref_array_compareAndExchangeAt(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(at: index, expect: expect, update: update)
}
