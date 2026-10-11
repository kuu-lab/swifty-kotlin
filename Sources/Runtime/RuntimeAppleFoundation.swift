import Foundation
#if canImport(Darwin)
import CoreFoundation
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func foundationFailure(_ message: String, _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    thrown?.pointee = runtimeAllocateIllegalArgumentException(message: message)
    return runtimeNullSentinelInt
}

/// A materialized function value, never guessed as a raw fn/env pair. Kotlin
/// declares the private argument Any, so ABI lowering preserves one word.
final class RuntimeFoundationCallback: @unchecked Sendable {
    let function: Int
    let capture: Int
    init?(_ function: Int) {
        guard let value = runtimeFunctionValueBox(from: function) else { return nil }
        self.function = function
        capture = value.closureRaw
    }
    func invoke(_ operation: Int, _ a: Int, _ b: Int, thrown: UnsafeMutablePointer<Int>?) -> Int {
        let pin = RuntimeForeignCallbackPin(root: capture)
        defer { withExtendedLifetime(pin) {} }
        return kk_function_invoke_3(function, operation, a, b, thrown)
    }
    func invoke0(thrown: UnsafeMutablePointer<Int>?) -> Int {
        let pin = RuntimeForeignCallbackPin(root: capture)
        defer { withExtendedLifetime(pin) {} }
        return kk_function_invoke_0(function, thrown)
    }
}

/// Queued SDK blocks must not keep a Kotlin pin after their run loop stops.
/// Cancellation drops the pin, and the retained native block becomes inert.
final class RuntimeFoundationRunLoopTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var pin: RuntimeForeignCallbackPin?
    private var cancelled = false
    let callback: RuntimeFoundationCallback
    init(_ callback: RuntimeFoundationCallback) {
        self.callback = callback
        pin = RuntimeForeignCallbackPin(root: callback.capture)
    }
    func invoke() {
        let held = lock.withLock { cancelled ? nil : pin }
        guard let held else { return }
        defer { cancel(); withExtendedLifetime(held) {} }
        var thrown = 0
        _ = callback.invoke0(thrown: &thrown)
        if thrown != 0 { kk_native_terminateWithUnhandledException(thrown) }
    }
    func cancel() {
        let retired = lock.withLock { () -> RuntimeForeignCallbackPin? in
            cancelled = true
            let held = pin
            pin = nil
            return held
        }
        withExtendedLifetime(retired) {}
    }
}

final class RuntimeFoundationRunLoopTickets: @unchecked Sendable {
    static let shared = RuntimeFoundationRunLoopTickets()
    private func key(_ loop: RunLoop) -> UInt {
        #if canImport(Darwin)
        UInt(bitPattern: Unmanaged.passUnretained(loop.getCFRunLoop()).toOpaque())
        #else
        UInt(bitPattern: Unmanaged.passUnretained(loop).toOpaque())
        #endif
    }
    private let lock = NSLock()
    private var entries: [UInt: [ObjectIdentifier: RuntimeFoundationRunLoopTicket]] = [:]
    func add(_ ticket: RuntimeFoundationRunLoopTicket, loop: RunLoop) {
        lock.withLock { entries[key(loop), default: [:]][ObjectIdentifier(ticket)] = ticket }
    }
    func finish(_ ticket: RuntimeFoundationRunLoopTicket, loop: RunLoop) {
        lock.withLock { _ = entries[key(loop)]?.removeValue(forKey: ObjectIdentifier(ticket)) }
    }
    func cancel(loop: RunLoop) { cancel(key: key(loop)) }
    func cancel(key: UInt) {
        let retired = lock.withLock { entries.removeValue(forKey: key) ?? [:] }
        for ticket in retired.values { ticket.cancel() }
    }
}

#if canImport(Darwin)
/// Holds the original Kotlin throwable in NSError.userInfo without retyping it
/// into an invented Kotlin NSData/NSError implementation.
final class RuntimeFoundationKotlinError: NSObject {
    let raw: Int
    private let pin: RuntimeForeignCallbackPin
    init(_ raw: Int) { self.raw = raw; pin = RuntimeForeignCallbackPin(root: raw); super.init() }
}

final class RuntimeFoundationStreamDispatch: @unchecked Sendable {
    let callback: RuntimeFoundationCallback
    var pendingThrown: Int = 0
    init(_ callback: RuntimeFoundationCallback) { self.callback = callback }
    func invoke(_ operation: Int, _ a: Int = runtimeNullSentinelInt,
                _ b: Int = runtimeNullSentinelInt) -> Int {
        var thrown = 0
        let result = callback.invoke(operation, a, b, thrown: &thrown)
        if thrown != 0 { pendingThrown = thrown }
        return result
    }
    var error: NSError? {
        let raw = invoke(3)
        if let error = runtimeForeignResourceForOwner(raw, as: NSError.self) { return error }
        if pendingThrown != 0 {
            return NSError(domain: "Kotlin", code: 0, userInfo: [
                NSUnderlyingErrorKey: RuntimeFoundationKotlinError(pendingThrown),
                NSLocalizedDescriptionKey: "Kotlin stream callback failed",
            ])
        }
        return nil
    }
}

/// Real Foundation SDK subclass. All IO/state decisions enter the Kotlin
/// controller. Foundation retains neither a fake NSData nor an array model.
final class RuntimeFoundationInputStream: InputStream {
    let dispatch: RuntimeFoundationStreamDispatch
    init(_ dispatch: RuntimeFoundationStreamDispatch) {
        self.dispatch = dispatch
        super.init(data: Data())
    }
    required init?(coder: NSCoder) { return nil }
    override func open() { _ = dispatch.invoke(0) }
    override func close() { _ = dispatch.invoke(1) }
    override var streamStatus: Stream.Status { Stream.Status(rawValue: UInt(maybeUnbox(dispatch.invoke(2)))) ?? .error }
    override var streamError: Error? { dispatch.error }
    override var hasBytesAvailable: Bool { maybeUnbox(dispatch.invoke(6)) != 0 }
    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard len >= 0 else { return -1 }
        let pointer = registerRuntimeObject(RuntimeCPointerBox(
            address: UInt(bitPattern: buffer), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.UByteVar")))
        defer { _ = runtimeReleaseObject(pointer) }
        let result = dispatch.invoke(4, pointer, kk_box_long(len))
        return dispatch.pendingThrown == 0 ? maybeUnbox(result) : -1
    }
    override func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, length len: UnsafeMutablePointer<Int>?) -> Bool { false }
    override func property(forKey key: Stream.PropertyKey) -> Any? {
        let raw = dispatch.invoke(8, runtimeMakeStringRaw(key.rawValue))
        return runtimeForeignResourceForOwner(raw, as: NSObject.self)
    }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        let token = runtimeForeignResourceCreate(aRunLoop)
        defer { runtimeForeignResourceDiscardUnattached(token) }
        _ = dispatch.invoke(9, kk_box_long(token), runtimeMakeStringRaw(mode.rawValue))
    }
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        let token = runtimeForeignResourceCreate(aRunLoop)
        defer { runtimeForeignResourceDiscardUnattached(token) }
        _ = dispatch.invoke(10, kk_box_long(token), runtimeMakeStringRaw(mode.rawValue))
    }
}

final class RuntimeFoundationOutputStream: OutputStream {
    let dispatch: RuntimeFoundationStreamDispatch
    init(_ dispatch: RuntimeFoundationStreamDispatch) { self.dispatch = dispatch; super.init(toMemory: ()) }
    required init?(coder: NSCoder) { return nil }
    override func open() { _ = dispatch.invoke(0) }
    override func close() { _ = dispatch.invoke(1) }
    override var streamStatus: Stream.Status { Stream.Status(rawValue: UInt(maybeUnbox(dispatch.invoke(2)))) ?? .error }
    override var streamError: Error? { dispatch.error }
    override var hasSpaceAvailable: Bool { maybeUnbox(dispatch.invoke(7)) != 0 }
    override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        guard len >= 0 else { return -1 }
        let pointer = registerRuntimeObject(RuntimeCPointerBox(
            address: UInt(bitPattern: buffer), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.UByteVar")))
        defer { _ = runtimeReleaseObject(pointer) }
        let result = dispatch.invoke(5, pointer, kk_box_long(len))
        return dispatch.pendingThrown == 0 ? maybeUnbox(result) : -1
    }
    override func property(forKey key: Stream.PropertyKey) -> Any? {
        let raw = dispatch.invoke(8, runtimeMakeStringRaw(key.rawValue))
        return runtimeForeignResourceForOwner(raw, as: NSObject.self)
    }
    override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }
    override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        let token = runtimeForeignResourceCreate(aRunLoop)
        defer { runtimeForeignResourceDiscardUnattached(token) }
        _ = dispatch.invoke(9, kk_box_long(token), runtimeMakeStringRaw(mode.rawValue))
    }
    override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {
        let token = runtimeForeignResourceCreate(aRunLoop)
        defer { runtimeForeignResourceDiscardUnattached(token) }
        _ = dispatch.invoke(10, kk_box_long(token), runtimeMakeStringRaw(mode.rawValue))
    }
}

/// SDK delegate is weak. Lease retains only this proxy, whose Kotlin closure
/// consults a Kotlin WeakReference on each event, never a captured delegate.
final class RuntimeFoundationStreamDelegate: NSObject, StreamDelegate {
    let callback: RuntimeFoundationCallback
    init(_ callback: RuntimeFoundationCallback) { self.callback = callback }
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        let pin = RuntimeForeignCallbackPin(root: callback.capture)
        defer { withExtendedLifetime(pin) {} }
        var thrown = 0
        _ = kk_function_invoke(callback.function, Int(eventCode.rawValue), &thrown)
        if thrown != 0 {
            // Delegate failures cannot unwind Objective-C. Use Kotlin's real
            // unhandled-exception hook rather than silently dropping them.
            kk_native_terminateWithUnhandledException(thrown)
        }
    }
}

func foundationStreamDispatch(_ stream: Stream) -> RuntimeFoundationStreamDispatch? {
    (stream as? RuntimeFoundationInputStream)?.dispatch ?? (stream as? RuntimeFoundationOutputStream)?.dispatch
}

func foundationStreamCall(_ handle: Int, _ operation: Int, _ arg1: Int, _ arg2: Int,
                          _ thrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let stream = runtimeForeignResource(handle, as: Stream.self) else { return foundationFailure("Invalid Foundation stream", thrown) }
    switch operation {
    case 0: stream.open()
    case 1: stream.close()
    case 2: return kk_box_long(Int(stream.streamStatus.rawValue))
    case 3:
        guard let error = stream.streamError else { return runtimeNullSentinelInt }
        return kk_box_long(runtimeForeignResourceCreate(error as NSError))
    case 4:
        guard let input = stream as? InputStream,
              let pointer = resolveCPointerBox(from: arg1),
              let address = UnsafeMutablePointer<UInt8>(bitPattern: pointer.address) else { return kk_box_long(-1) }
        let count = maybeUnbox(arg2)
        guard count >= 0 else { return foundationFailure("NSUInteger exceeds supported native length", thrown) }
        let result = input.read(address, maxLength: count)
        if let dispatch = foundationStreamDispatch(stream), dispatch.pendingThrown != 0 { thrown?.pointee = dispatch.pendingThrown; dispatch.pendingThrown = 0 }
        return kk_box_long(result)
    case 5:
        guard let output = stream as? OutputStream,
              let pointer = resolveCPointerBox(from: arg1),
              let address = UnsafePointer<UInt8>(bitPattern: pointer.address) else { return kk_box_long(-1) }
        let count = maybeUnbox(arg2)
        guard count >= 0 else { return foundationFailure("NSUInteger exceeds supported native length", thrown) }
        let result = output.write(address, maxLength: count)
        if let dispatch = foundationStreamDispatch(stream), dispatch.pendingThrown != 0 { thrown?.pointee = dispatch.pendingThrown; dispatch.pendingThrown = 0 }
        return kk_box_long(result)
    case 6: return kk_box_bool((stream as? InputStream)?.hasBytesAvailable == true ? 1 : 0)
    case 7: return kk_box_bool((stream as? OutputStream)?.hasSpaceAvailable == true ? 1 : 0)
    case 8:
        guard let key = runtimeStringFromRaw(arg1), let value = stream.property(forKey: .init(rawValue: key)) else { return runtimeNullSentinelInt }
        guard let object = value as? NSObject else { return foundationFailure("Unsupported SDK stream property representation", thrown) }
        return kk_box_long(runtimeForeignResourceCreate(object))
    case 9, 10:
        guard let loop = runtimeForeignResource(maybeUnbox(arg1), as: RunLoop.self), let mode = runtimeStringFromRaw(arg2) else { return foundationFailure("Invalid SDK run loop/mode", thrown) }
        if operation == 9 { stream.schedule(in: loop, forMode: .init(rawValue: mode)) }
        else { stream.remove(from: loop, forMode: .init(rawValue: mode)) }
    case 12:
        guard let input = stream as? InputStream else { return kk_box_bool(0) }
        let pointerAddress = resolveCPointerBox(from: arg1)?.address ?? 0
        let lengthAddress = resolveCPointerBox(from: arg2)?.address ?? 0
        // Kotlin keeps nullable CPointer syntax; Foundation requires both native
        // outpointers. Reject missing/null storage before the SDK call, as the
        // read/write cases reject missing native buffers. Valid outputs retain
        // their original addresses and are written directly by Foundation.
        guard let buffer = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>(bitPattern: pointerAddress),
              let length = UnsafeMutablePointer<Int>(bitPattern: lengthAddress) else { return kk_box_bool(0) }
        return kk_box_bool(input.getBuffer(buffer, length: length) ? 1 : 0)
    case 11:
        guard let key = runtimeStringFromRaw(arg2) else { return foundationFailure("Invalid SDK property key", thrown) }
        let value = runtimeForeignResourceForOwner(arg1, as: NSObject.self)
        return kk_box_bool(stream.setProperty(value, forKey: .init(rawValue: key)) ? 1 : 0)
    default: return foundationFailure("Unknown SDK stream operation", thrown)
    }
    if let dispatch = foundationStreamDispatch(stream), dispatch.pendingThrown != 0 { thrown?.pointee = dispatch.pendingThrown; dispatch.pendingThrown = 0 }
    return kk_box_unit(0)
}
#endif
