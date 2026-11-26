import Dispatch
import Foundation

func makePthreadKey() -> pthread_key_t {
    var key = pthread_key_t()
    #if canImport(Glibc) || canImport(Musl)
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer?) in
        guard let ptr else { return }
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #else
    pthread_key_create(&key) { (ptr: UnsafeMutableRawPointer) in
        Unmanaged<AnyObject>.fromOpaque(ptr).release()
    }
    #endif
    return key
}
func pthreadGetValue<T: AnyObject>(_ key: pthread_key_t) -> T? {
    guard let raw = pthread_getspecific(key) else { return nil }
    return Unmanaged<T>.fromOpaque(raw).takeUnretainedValue()
}

func pthreadSetValue<T: AnyObject>(_ key: pthread_key_t, _ value: T?) {
    if let prev = pthread_getspecific(key) {
        Unmanaged<AnyObject>.fromOpaque(prev).release()
    }
    if let value {
        let raw = Unmanaged.passRetained(value).toOpaque()
        pthread_setspecific(key, raw)
    } else {
        pthread_setspecific(key, nil)
    }
}

/// Identifier of a suspend-entry-loop invocation ("task").
///
/// Values are drawn from a global monotonic counter and are never reused, so a
/// map entry that outlives the invocation it belongs to (the async path leaves
/// entries in place for the resume-continuation chain) can never be picked up
/// by a later, unrelated invocation. An `ObjectIdentifier` of a per-invocation
/// token cannot give that guarantee: the allocator reuses the address of a
/// deallocated token, which silently aliases the two invocations and makes
/// `RuntimeContinuationState.current` / `RuntimeCoroutineScope.current` resolve
/// to another coroutine's state.
struct RuntimeTaskKey: Hashable, Sendable {
    let rawValue: UInt64

    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextRawValue: UInt64 = 1

    static func makeUnique() -> RuntimeTaskKey {
        lock.lock()
        let value = nextRawValue
        nextRawValue &+= 1
        lock.unlock()
        return RuntimeTaskKey(rawValue: value)
    }
}
