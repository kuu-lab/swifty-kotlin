import Foundation

private final class RuntimeThreadLocalBox {}

/// The pthread owns this token until the thread actually terminates. A
/// Foundation Thread object's address alone does not provide that lifetime.
private final class RuntimeThreadLocalOwner {
    deinit {
        let owner = ObjectIdentifier(self)
        runtimeStorage.withThreadLocalLock { state in
            guard let receivers = state.threadLocalReceiversByOwner.removeValue(forKey: owner) else {
                return
            }
            for receiver in receivers {
                state.threadLocalValues[receiver]?.removeValue(forKey: owner)
                if state.threadLocalValues[receiver]?.isEmpty == true {
                    state.threadLocalValues.removeValue(forKey: receiver)
                }
            }
        }
    }
}

private let runtimeThreadLocalOwnerKey = makePthreadKey()

private func runtimeThreadLocalOwner(create: Bool) -> RuntimeThreadLocalOwner? {
    if let existing: RuntimeThreadLocalOwner = pthreadGetValue(runtimeThreadLocalOwnerKey) {
        return existing
    }
    guard create else { return nil }
    let owner = RuntimeThreadLocalOwner()
    pthreadSetValue(runtimeThreadLocalOwnerKey, owner)
    return owner
}

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
    guard let owner = runtimeThreadLocalOwner(create: false) else { return 0 }
    let threadKey = ObjectIdentifier(owner)
    return runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[UInt(bitPattern: receiver)]?[threadKey] == nil ? 0 : 1
    }
}

@_cdecl("__kk_thread_local_value")
public func __kk_thread_local_value(_ receiver: Int) -> Int {
    guard let owner = runtimeThreadLocalOwner(create: false) else { return runtimeNullSentinelInt }
    let threadKey = ObjectIdentifier(owner)
    return runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[UInt(bitPattern: receiver)]?[threadKey] ?? runtimeNullSentinelInt
    }
}

@_cdecl("__kk_thread_local_store")
public func __kk_thread_local_store(_ receiver: Int, _ value: Int) -> Int {
    guard runtimeThreadLocalBox(from: receiver) != nil,
          let owner = runtimeThreadLocalOwner(create: true)
    else { return 0 }
    let threadKey = ObjectIdentifier(owner)
    let receiverKey = UInt(bitPattern: receiver)
    runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[receiverKey, default: [:]][threadKey] = value
        state.threadLocalReceiversByOwner[threadKey, default: []].insert(receiverKey)
    }
    return 0
}

@_cdecl("__kk_thread_local_remove")
public func __kk_thread_local_remove(_ receiver: Int) -> Int {
    guard runtimeThreadLocalBox(from: receiver) != nil,
          let owner = runtimeThreadLocalOwner(create: false)
    else { return 0 }
    let threadKey = ObjectIdentifier(owner)
    let receiverKey = UInt(bitPattern: receiver)
    runtimeStorage.withThreadLocalLock { state in
        state.threadLocalValues[receiverKey]?.removeValue(forKey: threadKey)
        if state.threadLocalValues[receiverKey]?.isEmpty == true {
            state.threadLocalValues.removeValue(forKey: receiverKey)
        }
        state.threadLocalReceiversByOwner[threadKey]?.remove(receiverKey)
        if state.threadLocalReceiversByOwner[threadKey]?.isEmpty == true {
            state.threadLocalReceiversByOwner.removeValue(forKey: threadKey)
        }
    }
    return 0
}
