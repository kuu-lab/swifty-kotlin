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

// Select receives share the same opaque ChannelResult representation as
// the ordinary Channel API, including failure and close causes.
@_cdecl("__kk_select_try_receive")
public func __kk_select_try_receive(_ handle: Int) -> Int {
    __kk_channel_try_receive(handle)
}

@_cdecl("__kk_select_receive_value")
public func __kk_select_receive_value(_ token: Int) -> Int {
    __kk_channel_result_value_or_null(token)
}
