import Foundation

// MARK: - AtomicInt

/// Backing storage for kotlin.concurrent.AtomicInt.
final class AtomicIntBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if storage == expect {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = old &+ delta
        return old
    }

    func addAndFetch(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage = storage &+ delta
        return storage
    }

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicIntBox(from raw: Int) -> AtomicIntBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicIntBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_int_create")
public func kk_atomic_int_create(_ initial: Int) -> Int {
    let box = AtomicIntBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_int_load")
public func kk_atomic_int_load(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_int_store")
public func kk_atomic_int_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_int_exchange")
public func kk_atomic_int_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_int_compareAndSet")
public func kk_atomic_int_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_int_compareAndExchange")
public func kk_atomic_int_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_atomic_int_fetchAndAdd")
public func kk_atomic_int_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("kk_atomic_int_addAndFetch")
public func kk_atomic_int_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("kk_atomic_int_fetchAndIncrement")
public func kk_atomic_int_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("kk_atomic_int_incrementAndFetch")
public func kk_atomic_int_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("kk_atomic_int_decrementAndFetch")
public func kk_atomic_int_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

@_cdecl("kk_atomic_int_getAndUpdate")
public func kk_atomic_int_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_int_updateAndGet")
public func kk_atomic_int_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}

// MARK: - AtomicIntArray

/// Backing storage for kotlin.concurrent.atomics.AtomicIntArray.
/// The array is protected by a single lock, which keeps the implementation
/// straightforward and preserves atomicity for every indexed operation.
final class AtomicIntArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        storage = Array(repeating: 0, count: max(0, size))
    }

    init(elements: [Int]) {
        storage = elements
    }

    func size() -> Int {
        storage.count
    }

    func toString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage.description
    }

    func get(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        return storage[index]
    }

    func set(index: Int, value: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        storage[index] = value
        return 0
    }

    func exchange(index: Int, new: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        storage[index] = new
        return old
    }

    func compareAndSet(index: Int, expect: Int, update: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        if storage[index] == expect {
            storage[index] = update
            return 1
        }
        return 0
    }

    func compareAndExchange(index: Int, expect: Int, update: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        if old == expect {
            storage[index] = update
        }
        return old
    }

    func fetchAndAdd(index: Int, delta: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        storage[index] = old &+ delta
        return old
    }

    func addAndFetch(index: Int, delta: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicIntArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        storage[index] = storage[index] &+ delta
        return storage[index]
    }

    func fetchAndIncrement(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        fetchAndAdd(index: index, delta: 1, outThrown: outThrown)
    }

    func incrementAndFetch(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        addAndFetch(index: index, delta: 1, outThrown: outThrown)
    }

    func fetchAndDecrement(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        fetchAndAdd(index: index, delta: -1, outThrown: outThrown)
    }

    func decrementAndFetch(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        addAndFetch(index: index, delta: -1, outThrown: outThrown)
    }

    func getAndUpdate(
        index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> (old: Int, new: Int) {
        while true {
            let old = get(index: index, outThrown: outThrown)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(index: index, expect: old, update: new, outThrown: outThrown) != 0 {
                return (old, new)
            }
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
        }
    }
}

private func atomicIntArrayBox(from raw: Int) -> AtomicIntArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicIntArrayBox>.fromOpaque(ptr).takeUnretainedValue()
}

private func runtimeAllocateAtomicIntArrayBox(_ box: AtomicIntArrayBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

private func runtimeAllocateAtomicString(_ value: String) -> Int {
    let box = RuntimeStringBox(value)
    return registerRuntimeObject(box)
}

@_cdecl("kk_atomic_int_array_create")
public func kk_atomic_int_array_create(_ size: Int) -> Int {
    runtimeAllocateAtomicIntArrayBox(AtomicIntArrayBox(size: size))
}

@_cdecl("kk_atomic_int_array_createFromArray")
public func kk_atomic_int_array_createFromArray(_ arrayRaw: Int) -> Int {
    guard let source = runtimeArrayBox(from: arrayRaw) else {
        return runtimeAllocateAtomicIntArrayBox(AtomicIntArrayBox(size: 0))
    }
    return runtimeAllocateAtomicIntArrayBox(AtomicIntArrayBox(elements: source.elements))
}

@_cdecl("kk_atomic_int_array_size")
public func kk_atomic_int_array_size(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_int_array_toString")
public func kk_atomic_int_array_toString(_ receiver: Int) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return runtimeAllocateAtomicString("[]") }
    return runtimeAllocateAtomicString(box.toString())
}

@_cdecl("kk_atomic_int_array_get")
public func kk_atomic_int_array_get(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.get(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_set")
public func kk_atomic_int_array_set(_ receiver: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.set(index: index, value: value, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_exchange")
public func kk_atomic_int_array_exchange(_ receiver: Int, _ index: Int, _ new: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.exchange(index: index, new: new, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_compareAndSet")
public func kk_atomic_int_array_compareAndSet(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.compareAndSet(index: index, expect: expect, update: update, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_compareAndExchange")
public func kk_atomic_int_array_compareAndExchange(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(index: index, expect: expect, update: update, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_getAndAdd")
public func kk_atomic_int_array_getAndAdd(_ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(index: index, delta: delta, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_addAndGet")
public func kk_atomic_int_array_addAndGet(_ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(index: index, delta: delta, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_getAndIncrement")
public func kk_atomic_int_array_getAndIncrement(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.fetchAndIncrement(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_incrementAndGet")
public func kk_atomic_int_array_incrementAndGet(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.incrementAndFetch(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_getAndDecrement")
public func kk_atomic_int_array_getAndDecrement(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.fetchAndDecrement(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_decrementAndGet")
public func kk_atomic_int_array_decrementAndGet(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    return box.decrementAndFetch(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_int_array_getAndUpdate")
public func kk_atomic_int_array_getAndUpdate(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(index: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_int_array_updateAndGet")
public func kk_atomic_int_array_updateAndGet(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicIntArrayBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(index: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}

// MARK: - AtomicLongArray

/// Backing storage for kotlin.concurrent.atomics.AtomicLongArray.
/// Long values are represented as Int at the runtime ABI level.
final class AtomicLongArrayBox {
    private var storage: [Int]
    private let lock = NSLock()

    init(size: Int) {
        storage = Array(repeating: 0, count: max(0, size))
    }

    init(elements: [Int]) {
        storage = elements
    }

    func size() -> Int {
        storage.count
    }

    func toString() -> String {
        lock.lock()
        defer { lock.unlock() }
        return storage.description
    }

    func get(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        return storage[index]
    }

    func set(index: Int, value: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        storage[index] = value
        return 0
    }

    func exchange(index: Int, new: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        storage[index] = new
        return old
    }

    func compareAndSet(index: Int, expect: Int, update: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        if storage[index] == expect {
            storage[index] = update
            return 1
        }
        return 0
    }

    func compareAndExchange(index: Int, expect: Int, update: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        if old == expect {
            storage[index] = update
        }
        return old
    }

    func fetchAndAdd(index: Int, delta: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        let old = storage[index]
        storage[index] = old &+ delta
        return old
    }

    func addAndFetch(index: Int, delta: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        guard storage.indices.contains(index) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "AtomicLongArray index \(index) out of bounds for length \(storage.count)."
            )
            return 0
        }
        lock.lock()
        defer { lock.unlock() }
        storage[index] = storage[index] &+ delta
        return storage[index]
    }

    func fetchAndIncrement(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        fetchAndAdd(index: index, delta: 1, outThrown: outThrown)
    }

    func incrementAndFetch(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        addAndFetch(index: index, delta: 1, outThrown: outThrown)
    }

    func fetchAndDecrement(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        fetchAndAdd(index: index, delta: -1, outThrown: outThrown)
    }

    func decrementAndFetch(index: Int, outThrown: UnsafeMutablePointer<Int>?) -> Int {
        addAndFetch(index: index, delta: -1, outThrown: outThrown)
    }

    func getAndUpdate(
        index: Int,
        transform: (Int) -> Int,
        outThrown: UnsafeMutablePointer<Int>?
    ) -> (old: Int, new: Int) {
        while true {
            let old = get(index: index, outThrown: outThrown)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(index: index, expect: old, update: new, outThrown: outThrown) != 0 {
                return (old, new)
            }
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
        }
    }
}

private func atomicLongArrayBox(from raw: Int) -> AtomicLongArrayBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicLongArrayBox>.fromOpaque(ptr).takeUnretainedValue()
}

private func runtimeAllocateAtomicLongArrayBox(_ box: AtomicLongArrayBox) -> Int {
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_array_create")
public func kk_atomic_long_array_create(_ size: Int) -> Int {
    runtimeAllocateAtomicLongArrayBox(AtomicLongArrayBox(size: size))
}

@_cdecl("kk_atomic_long_array_createFromArray")
public func kk_atomic_long_array_createFromArray(_ arrayRaw: Int) -> Int {
    guard let source = runtimeArrayBox(from: arrayRaw) else {
        return runtimeAllocateAtomicLongArrayBox(AtomicLongArrayBox(size: 0))
    }
    return runtimeAllocateAtomicLongArrayBox(AtomicLongArrayBox(elements: source.elements))
}

@_cdecl("kk_atomic_long_array_size")
public func kk_atomic_long_array_size(_ receiver: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.size()
}

@_cdecl("kk_atomic_long_array_toString")
public func kk_atomic_long_array_toString(_ receiver: Int) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return runtimeAllocateAtomicString("[]") }
    return runtimeAllocateAtomicString(box.toString())
}

@_cdecl("kk_atomic_long_array_get")
public func kk_atomic_long_array_get(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.get(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_set")
public func kk_atomic_long_array_set(_ receiver: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.set(index: index, value: value, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_exchange")
public func kk_atomic_long_array_exchange(_ receiver: Int, _ index: Int, _ new: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.exchange(index: index, new: new, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_compareAndSet")
public func kk_atomic_long_array_compareAndSet(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.compareAndSet(index: index, expect: expect, update: update, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_compareAndExchange")
public func kk_atomic_long_array_compareAndExchange(_ receiver: Int, _ index: Int, _ expect: Int, _ update: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.compareAndExchange(index: index, expect: expect, update: update, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_getAndAdd")
public func kk_atomic_long_array_getAndAdd(_ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(index: index, delta: delta, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_addAndGet")
public func kk_atomic_long_array_addAndGet(_ receiver: Int, _ index: Int, _ delta: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.addAndFetch(index: index, delta: delta, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_getAndIncrement")
public func kk_atomic_long_array_getAndIncrement(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.fetchAndIncrement(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_incrementAndGet")
public func kk_atomic_long_array_incrementAndGet(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.incrementAndFetch(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_getAndDecrement")
public func kk_atomic_long_array_getAndDecrement(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.fetchAndDecrement(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_decrementAndGet")
public func kk_atomic_long_array_decrementAndGet(_ receiver: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    return box.decrementAndFetch(index: index, outThrown: outThrown)
}

@_cdecl("kk_atomic_long_array_getAndUpdate")
public func kk_atomic_long_array_getAndUpdate(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(index: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_long_array_updateAndGet")
public func kk_atomic_long_array_updateAndGet(
    _ receiver: Int,
    _ index: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongArrayBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(index: index, transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}

// MARK: - AtomicLong

/// Backing storage for kotlin.concurrent.AtomicLong.
final class AtomicLongBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if storage == expect {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }

    func fetchAndAdd(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = old &+ delta
        return old
    }

    func addAndFetch(_ delta: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        storage = storage &+ delta
        return storage
    }

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicLongBox(from raw: Int) -> AtomicLongBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicLongBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_long_create")
public func kk_atomic_long_create(_ initial: Int) -> Int {
    let box = AtomicLongBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_long_load")
public func kk_atomic_long_load(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_long_store")
public func kk_atomic_long_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_long_exchange")
public func kk_atomic_long_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_long_compareAndSet")
public func kk_atomic_long_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_long_compareAndExchange")
public func kk_atomic_long_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_atomic_long_fetchAndAdd")
public func kk_atomic_long_fetchAndAdd(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(delta)
}

@_cdecl("kk_atomic_long_addAndFetch")
public func kk_atomic_long_addAndFetch(_ receiver: Int, _ delta: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(delta)
}

@_cdecl("kk_atomic_long_fetchAndIncrement")
public func kk_atomic_long_fetchAndIncrement(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.fetchAndAdd(1)
}

@_cdecl("kk_atomic_long_incrementAndFetch")
public func kk_atomic_long_incrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(1)
}

@_cdecl("kk_atomic_long_decrementAndFetch")
public func kk_atomic_long_decrementAndFetch(_ receiver: Int) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    return box.addAndFetch(-1)
}

@_cdecl("kk_atomic_long_getAndUpdate")
public func kk_atomic_long_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_long_updateAndGet")
public func kk_atomic_long_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicLongBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}

// MARK: - AtomicBoolean

/// Backing storage for kotlin.concurrent.AtomicBoolean.
/// Boolean values are stored as Int: 1 = true, 0 = false.
final class AtomicBooleanBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Bool) {
        self.storage = initial ? 1 : 0
    }

    func load() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage != 0
    }

    func store(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        storage = value ? 1 : 0
    }

    func exchange(_ new: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = storage != 0
        storage = new ? 1 : 0
        return old
    }

    func compareAndSet(expect: Bool, update: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let expectInt = expect ? 1 : 0
        if storage == expectInt {
            storage = update ? 1 : 0
            return true
        }
        return false
    }

    func compareAndExchange(expect: Bool, update: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = storage != 0
        if storage == (expect ? 1 : 0) {
            storage = update ? 1 : 0
        }
        return old
    }

    func getAndUpdate(transform: (Bool) -> Bool, outThrown: UnsafeMutablePointer<Int>?) -> (old: Bool, new: Bool) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicBoolBox(from raw: Int) -> AtomicBooleanBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicBooleanBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_bool_create")
public func kk_atomic_bool_create(_ initial: Int) -> Int {
    let box = AtomicBooleanBox(initial: initial != 0)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_bool_load")
public func kk_atomic_bool_load(_ receiver: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.load() ? 1 : 0
}

@_cdecl("kk_atomic_bool_store")
public func kk_atomic_bool_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    box.store(value != 0)
    return 0
}

@_cdecl("kk_atomic_bool_exchange")
public func kk_atomic_bool_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.exchange(new != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_compareAndSet")
public func kk_atomic_bool_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect != 0, update: update != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_compareAndExchange")
public func kk_atomic_bool_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect != 0, update: update != 0) ? 1 : 0
}

@_cdecl("kk_atomic_bool_getAndUpdate")
public func kk_atomic_bool_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }, outThrown: outThrown)
    return result.old ? 1 : 0
}

@_cdecl("kk_atomic_bool_updateAndGet")
public func kk_atomic_bool_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicBoolBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old ? 1 : 0, outThrown) != 0
    }, outThrown: outThrown)
    return result.new ? 1 : 0
}

// MARK: - AtomicReference<T>

/// Backing storage for kotlin.concurrent.AtomicReference<T>.
/// Values are stored as opaque intptr_t (object pointers or boxed values).
final class AtomicRefBox {
    private var storage: Int
    private let lock = NSLock()

    init(initial: Int) {
        self.storage = initial
    }

    func load() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func store(_ value: Int) {
        lock.lock()
        defer { lock.unlock() }
        storage = value
    }

    func exchange(_ new: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        storage = new
        return old
    }

    func compareAndSet(expect: Int, update: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if storage == expect {
            storage = update
            return true
        }
        return false
    }

    func compareAndExchange(expect: Int, update: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let old = storage
        if old == expect {
            storage = update
        }
        return old
    }

    func getAndUpdate(transform: (Int) -> Int, outThrown: UnsafeMutablePointer<Int>?) -> (old: Int, new: Int) {
        while true {
            let old = load()
            let new = transform(old)
            if let thrown = outThrown, thrown.pointee != 0 {
                return (old, old)
            }
            if compareAndSet(expect: old, update: new) {
                return (old, new)
            }
        }
    }
}

private func atomicRefBox(from raw: Int) -> AtomicRefBox? {
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    return Unmanaged<AtomicRefBox>.fromOpaque(ptr).takeUnretainedValue()
}

@_cdecl("kk_atomic_ref_create")
public func kk_atomic_ref_create(_ initial: Int) -> Int {
    let box = AtomicRefBox(initial: initial)
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("kk_atomic_ref_load")
public func kk_atomic_ref_load(_ receiver: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.load()
}

@_cdecl("kk_atomic_ref_store")
public func kk_atomic_ref_store(_ receiver: Int, _ value: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    box.store(value)
    return 0
}

@_cdecl("kk_atomic_ref_exchange")
public func kk_atomic_ref_exchange(_ receiver: Int, _ new: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.exchange(new)
}

@_cdecl("kk_atomic_ref_compareAndSet")
public func kk_atomic_ref_compareAndSet(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndSet(expect: expect, update: update) ? 1 : 0
}

@_cdecl("kk_atomic_ref_compareAndExchange")
public func kk_atomic_ref_compareAndExchange(_ receiver: Int, _ expect: Int, _ update: Int) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    return box.compareAndExchange(expect: expect, update: update)
}

@_cdecl("kk_atomic_ref_getAndUpdate")
public func kk_atomic_ref_getAndUpdate(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.old
}

@_cdecl("kk_atomic_ref_updateAndGet")
public func kk_atomic_ref_updateAndGet(
    _ receiver: Int,
    _ updateFn: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let box = atomicRefBox(from: receiver) else { return 0 }
    let result = box.getAndUpdate(transform: { old in
        kk_function_invoke(updateFn, old, outThrown)
    }, outThrown: outThrown)
    return result.new
}
