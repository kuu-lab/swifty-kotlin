@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package platform.CoreFoundation
public typealias CFRunLoopRef = kotlinx.cinterop.CPointer<*>
public fun CFRunLoopStop(runLoop: CFRunLoopRef) {
    platform.Foundation.__foundation_runloop_stop(runLoop)
}
