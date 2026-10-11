package platform.Foundation
public class NSRunLoop internal constructor(handle: Long) : NSObject(handle) {
    public companion object { public val currentRunLoop: NSRunLoop get() = NSRunLoop(__foundation_runloop_current()) }
    public fun performInModes(modes: List<NSRunLoopMode>, block: () -> Unit) {
        __foundation_runloop_perform(__handle, modes.toTypedArray(), block as Any)
    }
    public fun run() { __foundation_runloop_run(__handle) }
    public fun getCFRunLoop(): platform.CoreFoundation.CFRunLoopRef = __foundation_runloop_cf_pointer(__handle)
    public fun addPort(port: NSMachPort, forMode: NSRunLoopMode) {
        __foundation_runloop_add_port(__handle, port.__handle, forMode)
    }
}
public class NSMachPort internal constructor(handle: Long) : NSObject(handle) {
    public companion object { public fun port(): NSMachPort = NSMachPort(__foundation_port_create()) }
}
public class NSThread internal constructor(handle: Long) : NSObject(handle) {
    public constructor(block: () -> Unit) : this(__foundation_thread_create(block as Any))
    public var name: String? get() = __foundation_thread_name(__handle)
        set(value) { __foundation_thread_set_name(__handle, value) }
    public fun start() { __foundation_thread_start(__handle) }
    public companion object { public val currentThread: NSThread get() = NSThread(__foundation_thread_current()) }
}
public class NSRecursiveLock internal constructor(handle: Long) : NSObject(handle) {
    public constructor() : this(__foundation_lock_create())
    public fun lock() { __foundation_lock_lock(__handle) }
    public fun unlock() { __foundation_lock_unlock(__handle) }
}
