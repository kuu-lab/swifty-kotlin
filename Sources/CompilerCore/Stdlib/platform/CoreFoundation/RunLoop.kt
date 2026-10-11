@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package platform.CoreFoundation
// Opaque native CF pointer. Nominal __CFRunLoop pointee import is deferred with
// the general SDK importer; this facade never constructs a fake NSRunLoop.
public typealias CFRunLoopRef = kotlinx.cinterop.CPointer<*>
public fun CFRunLoopStop(runLoop: CFRunLoopRef) {
    platform.Foundation.__foundation_runloop_stop(runLoop)
}
