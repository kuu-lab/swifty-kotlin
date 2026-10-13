import Foundation

private final class RuntimeThreadLocalBox {}

private func runtimeThreadLocalBox(from rawValue: Int) -> RuntimeThreadLocalBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: rawValue) else {
        return nil
    }
    let isThreadLocalBox = runtimeStorage.withThreadLocalLock { state in
        state.threadLocalBoxes.contains(UInt(bitPattern: ptr))
    }
    guard isThreadLocalBox else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThreadLocalBox.self)
}

@_cdecl("__kk_thread_local_new")
public func __kk_thread_local_new() -> Int {
    let box = RuntimeThreadLocalBox()
    let ptr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withThreadLocalLock { state in
        state.threadLocalBoxes.insert(UInt(bitPattern: ptr))
    }
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: ptr))
    }
    return Int(bitPattern: ptr)
}

@_cdecl("__kk_thread_local_has_value")
public func __kk_thread_local_has_value(_ receiver: Int) -> Int {
    let threadKey = ObjectIdentifier(Thread.current)
    return runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[UInt(bitPattern: receiver)]?[threadKey] == nil ? 0 : 1
    }
}

@_cdecl("__kk_thread_local_value")
public func __kk_thread_local_value(_ receiver: Int) -> Int {
    let threadKey = ObjectIdentifier(Thread.current)
    return runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[UInt(bitPattern: receiver)]?[threadKey] ?? runtimeNullSentinelInt
    }
}

@_cdecl("__kk_thread_local_store")
public func __kk_thread_local_store(_ receiver: Int, _ value: Int) -> Int {
    guard runtimeThreadLocalBox(from: receiver) != nil else { return 0 }
    let threadKey = ObjectIdentifier(Thread.current)
    runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[UInt(bitPattern: receiver), default: [:]][threadKey] = value
    }
    return 0
}
