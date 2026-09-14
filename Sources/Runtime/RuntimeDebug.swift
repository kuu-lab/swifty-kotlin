import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

private let runtimeAssertionStateLock = NSLock()
private nonisolated(unsafe) var runtimeAssertionsEnabled = runtimeInitialAssertionsEnabled()

private func runtimeInitialAssertionsEnabled() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    for key in ["KK_ASSERTIONS_ENABLED", "KOTLIN_ASSERTIONS_ENABLED"] {
        guard let rawValue = environment[key]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawValue.isEmpty
        else {
            continue
        }
        switch rawValue {
        case "0", "false", "no", "off":
            return false
        case "1", "true", "yes", "on":
            return true
        default:
            continue
        }
    }
    return true
}

func runtimeAreAssertionsEnabled() -> Bool {
    runtimeAssertionStateLock.lock()
    defer { runtimeAssertionStateLock.unlock() }
    return runtimeAssertionsEnabled
}

func runtimeSetAssertionsEnabled(_ enabled: Bool) {
    runtimeAssertionStateLock.lock()
    runtimeAssertionsEnabled = enabled
    runtimeAssertionStateLock.unlock()
}

func runtimeResetDebugState() {
    runtimeSetAssertionsEnabled(runtimeInitialAssertionsEnabled())
}

// (b) RF-DEAD-002: テスト支援 API — Kotlin プログラムから直接呼ばれない。
// RuntimeTests がテスト間で assert 状態を検査・リセットするためのセム。
@_cdecl("__kk_assertions_enabled")
public func __kk_assertions_enabled() -> Int {
    runtimeAreAssertionsEnabled() ? 1 : 0
}

@_cdecl("kk_assertions_set_enabled")
public func kk_assertions_set_enabled(_ enabled: Int) -> Int {
    runtimeSetAssertionsEnabled(enabled != 0)
    return 0
}

@_cdecl("kk_assertions_reset")
public func kk_assertions_reset() -> Int {
    runtimeResetDebugState()
    return 0
}

// KSP-1260: the public `kotlin.native.runtime.Debugging` surface lives in
// bundled Kotlin source (Stdlib/kotlin/native/runtime/Debugging.kt). Only the
// runtime entry points stay here, demoted to `__kk_` so they are reachable
// from the stdlib layer alone.
@_cdecl("__kk_debugging_is_thread_state_runnable")
public func __kk_debugging_is_thread_state_runnable() -> Int {
    1
}

private let debuggingForceCheckedShutdownLock = NSLock()
private nonisolated(unsafe) var debuggingForceCheckedShutdownState = false

@_cdecl("__kk_debugging_force_checked_shutdown_get")
public func __kk_debugging_force_checked_shutdown_get() -> Int {
    debuggingForceCheckedShutdownLock.lock()
    defer { debuggingForceCheckedShutdownLock.unlock() }
    return debuggingForceCheckedShutdownState ? 1 : 0
}

@_cdecl("__kk_debugging_force_checked_shutdown_set")
public func __kk_debugging_force_checked_shutdown_set(_ value: Int) -> Int {
    debuggingForceCheckedShutdownLock.lock()
    debuggingForceCheckedShutdownState = value != 0
    debuggingForceCheckedShutdownLock.unlock()
    return 0
}

/// Dumps a short heap-allocation summary into `fd` via a raw POSIX `write`,
/// so an invalid descriptor reports failure instead of trapping the process.
@_cdecl("__kk_debugging_dump_memory")
public func __kk_debugging_dump_memory(_ fd: Int) -> Int {
    let summary = runtimeStorage.withGCLock { state in
        "kswiftc heap dump: objects=\(state.objectPointers.count + state.heapObjects.count)\n"
    }
    let bytes = Array(summary.utf8)
    let descriptor = Int32(truncatingIfNeeded: fd)
    let written = bytes.withUnsafeBufferPointer { buffer -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        return write(descriptor, base, buffer.count)
    }
    return written == bytes.count ? 1 : 0
}

@_cdecl("kk_debugging_gc_suspend_count")
public func kk_debugging_gc_suspend_count() -> Int {
    0
}

@_cdecl("kk_debugging_thread_count")
public func kk_debugging_thread_count() -> Int {
    1
}

@_cdecl("kk_debugging_global_object_count")
public func kk_debugging_global_object_count() -> Int {
    runtimeStorage.withGCLock { state in
        state.objectPointers.count + state.heapObjects.count
    }
}
