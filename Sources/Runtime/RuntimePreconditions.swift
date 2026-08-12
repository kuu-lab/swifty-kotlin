import Foundation

// Runtime support for kotlin.assert (STDLIB-258).
// The require/check/error precondition family is implemented in bundled Kotlin
// source (Stdlib/kotlin/Preconditions.kt) and lowered through the standard
// exception allocation helpers below.

// MARK: - assert (STDLIB-258)

@_cdecl("kk_precondition_assert")
public func kk_precondition_assert(_ condition: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeAreAssertionsEnabled() else {
        return 0
    }
    if condition == 0 {
        outThrown?.pointee = runtimeAllocateAssertionError(message: "Assertion failed")
        return 0
    }
    return 0
}

@_cdecl("kk_precondition_assert_lazy")
public func kk_precondition_assert_lazy(
    _ condition: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard runtimeAreAssertionsEnabled() else {
        return 0
    }
    guard condition == 0 else {
        return 0
    }
    guard fnPtr != 0 else {
        outThrown?.pointee = runtimeAllocateAssertionError(message: "Assertion failed")
        return 0
    }

    var lazyThrown = 0
    let rawMessage = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &lazyThrown)
    if lazyThrown != 0 {
        outThrown?.pointee = runtimeAllocateAssertionError(
            message: "Assertion failed",
            cause: lazyThrown
        )
        return 0
    }

    let message = runtimePreconditionMessage(from: rawMessage)
    outThrown?.pointee = runtimeAllocateAssertionError(message: message)
    return 0
}

func runtimePreconditionMessage(from rawValue: Int) -> String {
    if let message = extractString(from: UnsafeMutableRawPointer(bitPattern: rawValue)) {
        return message
    }
    if rawValue == runtimeNullSentinelInt {
        return "null"
    }
    guard let pointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return String(rawValue)
    }
    if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
        return boolBox.value ? "true" : "false"
    }
    if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
        return String(intBox.value)
    }
    if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
        return String(longBox.value)
    }
    if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
        return String(UInt(bitPattern: ulongBox.value))
    }
    if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
        return String(doubleBox.value)
    }
    if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
        return String(floatBox.value)
    }
    if let charBox = tryCast(pointer, to: RuntimeCharBox.self),
       let scalar = UnicodeScalar(charBox.value)
    {
        return String(Character(scalar))
    }
    if let throwable = tryCast(pointer, to: RuntimeThrowableBox.self) {
        return throwable.message
    }
    return "<object \(pointer)>"
}

// MARK: - synchronized (STDLIB-325 / KSP-618)

/// Runtime support for kotlin.synchronized(lock, block).
/// Uses NSRecursiveLock-based per-object locking. The lock argument is used as a key
/// to obtain a reentrant lock, and the block lambda is executed under that lock.
/// The public `synchronized` layer is Kotlin source (Stdlib/kotlin/Synchronized.kt)
/// delegating to this demoted bridge.
@_cdecl("__kk_synchronized")
public func __kk_synchronized(_ lock: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

@_cdecl("kk_reentrant_read_write_lock_read")
public func kk_reentrant_read_write_lock_read(
    _ lock: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let nsLock = runtimeGetOrCreateLock(for: lock)
    nsLock.lock()
    defer { nsLock.unlock() }

    var thrown = 0
    let result = runtimeInvokeClosureThunk(fnPtr: fnPtr, closureRaw: closureRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

private let runtimeLockStorage = NSLock()
private nonisolated(unsafe) var runtimeLocks: [Int: NSRecursiveLock] = [:]

private func runtimeGetOrCreateLock(for key: Int) -> NSRecursiveLock {
    runtimeLockStorage.lock()
    defer { runtimeLockStorage.unlock() }
    if let existing = runtimeLocks[key] {
        return existing
    }
    let newLock = NSRecursiveLock()
    runtimeLocks[key] = newLock
    return newLock
}
