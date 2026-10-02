import Foundation

private let selectBuilderKey = "KSwiftK.selectBuilder"

@_cdecl("__kk_select_start_job")
public func __kk_select_start_job(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else { return 0 }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = object as? RuntimeJobHandle {
        job.startIfNeeded()
    } else if let task = object as? RuntimeAsyncTask {
        task.startIfNeeded()
    }
    return 0
}

@_cdecl("__kk_select_builder_exchange")
public func __kk_select_builder_exchange(_ builder: Int) -> Int {
    let previous = __kk_select_builder_current()
    if builder == runtimeNullSentinelInt {
        Thread.current.threadDictionary.removeObject(forKey: selectBuilderKey)
    } else {
        Thread.current.threadDictionary[selectBuilderKey] = builder
    }
    return previous
}

@_cdecl("__kk_select_builder_current")
public func __kk_select_builder_current() -> Int {
    Thread.current.threadDictionary[selectBuilderKey] as? Int ?? runtimeNullSentinelInt
}

private final class RuntimeSelectReceiveResult {
    let value: Int

    init(value: Int) {
        self.value = value
    }
}

@_cdecl("__kk_select_try_receive")
public func __kk_select_try_receive(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return ChannelOperationStatus.closed.rawValue
    }
    let channel = Unmanaged<RuntimeChannelHandle>.fromOpaque(ptr).takeUnretainedValue()
    let result = channel.tryReceive()
    guard result.status == .success else { return result.status.rawValue }
    let box = RuntimeSelectReceiveResult(value: result.value)
    let boxPtr = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: boxPtr))
    }
    return Int(bitPattern: boxPtr)
}

@_cdecl("__kk_select_receive_value")
public func __kk_select_receive_value(_ token: Int) -> Int {
    if token == ChannelOperationStatus.success.rawValue {
        return kk_box_unit(0)
    }
    guard token > 3 || token < 0, let ptr = UnsafeMutableRawPointer(bitPattern: token) else {
        return runtimeNullSentinelInt
    }
    return Unmanaged<RuntimeSelectReceiveResult>.fromOpaque(ptr).takeUnretainedValue().value
}
