import Foundation
#if canImport(Darwin)
import Darwin
import CoreFoundation
#elseif canImport(Glibc)
import Glibc
#endif

@_cdecl("__kk_foundation_attach")
public func __kk_foundation_attach(_ owner: Int, _ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeForeignResourceAttach(handle, owner: owner) else {
        runtimeForeignResourceDiscardUnattached(handle)
        return foundationFailure("Foreign SDK lease needs a live, unique Kotlin owner", outThrown)
    }
    return 0
}

@_cdecl("__kk_foundation_object_create")
public func __kk_foundation_object_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return runtimeForeignResourceCreate(NSObject())
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_object_kind")
public func __kk_foundation_object_kind(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let object = runtimeForeignResource(handle, as: NSObject.self) else { return foundationFailure("Invalid SDK handle", outThrown) }
    switch object {
    case is NSData: return 1
    case is NSError: return 2
    case is InputStream: return 3
    case is OutputStream: return 4
    case is RunLoop: return 5
    case is Thread: return 6
    default: return 0
    }
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_object_equals")
public func __kk_foundation_object_equals(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let a = runtimeForeignResource(lhs, as: NSObject.self), let b = runtimeForeignResource(rhs, as: NSObject.self) else { return foundationFailure("Invalid SDK equality receiver", outThrown) }
    return a.isEqual(b) ? 1 : 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_object_hash")
public func __kk_foundation_object_hash(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let object = runtimeForeignResource(handle, as: NSObject.self) else { return foundationFailure("Invalid SDK hash receiver", outThrown) }
    return Int(Int32(truncatingIfNeeded: object.hash))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_data_create")
public func __kk_foundation_data_create(_ bytes: Int, _ length: Int, _ noCopy: Int, _ freeWhenDone: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard length >= 0 else { return foundationFailure("NSData length exceeds Int.max", outThrown) }
    let address = resolveCPointerBox(from: bytes)?.address ?? 0
    let pointer = UnsafeMutableRawPointer(bitPattern: address)
    guard length == 0 || pointer != nil else { return foundationFailure("Null NSData bytes", outThrown) }
    if noCopy != 0 {
        if let pointer { return runtimeForeignResourceCreate(NSData(bytesNoCopy: pointer, length: length, freeWhenDone: freeWhenDone != 0)) }
        return runtimeForeignResourceCreate(NSData())
    }
    return runtimeForeignResourceCreate(NSData(bytes: pointer, length: length))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_data_base64")
public func __kk_foundation_data_base64(_ text: Int, _ options: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let text = runtimeStringFromRaw(text), let data = NSData(base64Encoded: text, options: .init(rawValue: UInt(bitPattern: options))) else { return runtimeNullSentinelInt }
    return kk_box_long_nonnull(runtimeForeignResourceCreate(data))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_data_length")
public func __kk_foundation_data_length(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let data = runtimeForeignResource(handle, as: NSData.self) else { return foundationFailure("Invalid NSData", outThrown) }
    return data.length
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_data_bytes")
public func __kk_foundation_data_bytes(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let data = runtimeForeignResource(handle, as: NSData.self) else { return foundationFailure("Invalid NSData", outThrown) }
    return registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: data.bytes),
        pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_error_create")
public func __kk_foundation_error_create(_ domain: Int, _ code: Int, _ description: Int, _ underlying: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let domain = runtimeStringFromRaw(domain) else { return foundationFailure("Invalid NSError domain", outThrown) }
    var info: [String: Any] = [:]
    if let description = runtimeStringFromRaw(description) { info[NSLocalizedDescriptionKey] = description }
    if underlying != 0 && underlying != runtimeNullSentinelInt { info[NSUnderlyingErrorKey] = RuntimeFoundationKotlinError(underlying) }
    return runtimeForeignResourceCreate(NSError(domain: domain, code: code, userInfo: info))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_error_description")
public func __kk_foundation_error_description(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let error = runtimeForeignResource(handle, as: NSError.self) else { return foundationFailure("Invalid NSError", outThrown) }
    return runtimeMakeStringRaw(error.localizedDescription)
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_url_file")
public func __kk_foundation_url_file(_ path: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let path = runtimeStringFromRaw(path) else { return foundationFailure("Invalid SDK URL path", outThrown) }
    return runtimeForeignResourceCreate(NSURL(fileURLWithPath: path))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_input_create")
public func __kk_foundation_input_create(_ data: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let data = runtimeForeignResource(data, as: NSData.self) else { return foundationFailure("Invalid input NSData", outThrown) }
    return runtimeForeignResourceCreate(InputStream(data: data as Data))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_input_url")
public func __kk_foundation_input_url(_ url: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let url = runtimeForeignResource(url, as: NSURL.self), let stream = InputStream(url: url as URL) else { return foundationFailure("Cannot create SDK input stream", outThrown) }
    return runtimeForeignResourceCreate(stream)
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_output_create")
public func __kk_foundation_output_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return runtimeForeignResourceCreate(OutputStream.toMemory())
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_stream_call")
public func __kk_foundation_stream_call(_ handle: Int, _ operation: Int, _ arg1: Int, _ arg2: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return foundationStreamCall(handle, operation, arg1, arg2, outThrown)
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_stream_install")
public func __kk_foundation_stream_install(_ handle: Int, _ block: Int, _ input: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let callback = RuntimeFoundationCallback(block),
          runtimeFunctionValueBox(from: block)?.arity == 3 else { return foundationFailure("SDK stream needs a materialized Function3", outThrown) }
    let dispatch = RuntimeFoundationStreamDispatch(callback)
    let stream: Stream = input != 0 ? RuntimeFoundationInputStream(dispatch) : RuntimeFoundationOutputStream(dispatch)
    let old = runtimeStorage.withGCLock { state -> RuntimeForeignResourceLease? in
        guard let old = state.foreignResources[handle], old.owner != nil else { return nil }
        let replacement = RuntimeForeignResourceLease(value: stream, dependentRoots: [UInt(bitPattern: callback.capture)])
        replacement.owner = old.owner
        state.foreignResources[handle] = replacement
        return old
    }
    guard old != nil else { return foundationFailure("SDK stream override needs attached owner", outThrown) }
    withExtendedLifetime(old) {}
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_stream_delegate")
public func __kk_foundation_stream_delegate(_ handle: Int, _ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let stream = runtimeForeignResource(handle, as: Stream.self) else { return foundationFailure("Invalid SDK stream", outThrown) }
    var proxy: RuntimeFoundationStreamDelegate?
    if block != 0 && block != runtimeNullSentinelInt {
        guard let callback = RuntimeFoundationCallback(block), runtimeFunctionValueBox(from: block)?.arity == 1 else { return foundationFailure("SDK delegate needs Function1", outThrown) }
        proxy = RuntimeFoundationStreamDelegate(callback)
    }
    let old = runtimeStorage.withGCLock { state -> [AnyObject] in
        guard let lease = state.foreignResources[handle] else { return [] }
        let old = lease.attachments
        lease.attachments = proxy.map { [$0] } ?? []
        lease.attachmentRoots = proxy.map { [UInt(bitPattern: $0.callback.capture)] } ?? []
        return old
    }
    stream.delegate = proxy
    withExtendedLifetime(old) {}
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_stream_event")
public func __kk_foundation_stream_event(_ handle: Int, _ event: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let stream = runtimeForeignResource(handle, as: Stream.self) else { return foundationFailure("Invalid SDK stream event receiver", outThrown) }
    stream.delegate?.stream?(stream, handle: .init(rawValue: UInt(bitPattern: event)))
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_runloop_current")
public func __kk_foundation_runloop_current(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return runtimeForeignResourceCreate(RunLoop.current)
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_runloop_perform")
public func __kk_foundation_runloop_perform(_ handle: Int, _ modes: Int, _ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let loop = runtimeForeignResource(handle, as: RunLoop.self),
          let modes = runtimeArrayBox(from: modes), let callback = RuntimeFoundationCallback(block),
          runtimeFunctionValueBox(from: block)?.arity == 0 else { return foundationFailure("Invalid SDK run loop block/modes", outThrown) }
    let names = modes.elements.compactMap(runtimeStringFromRaw)
    guard names.count == modes.count else { return foundationFailure("Invalid SDK run loop mode", outThrown) }
    let ticket = RuntimeFoundationRunLoopTicket(callback)
    RuntimeFoundationRunLoopTickets.shared.add(ticket, loop: loop)
    loop.perform(inModes: names.map { .init(rawValue: $0) }) { [weak loop] in
        ticket.invoke()
        if let loop { RuntimeFoundationRunLoopTickets.shared.finish(ticket, loop: loop) }
    }
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_runloop_run")
public func __kk_foundation_runloop_run(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let loop = runtimeForeignResource(handle, as: RunLoop.self) else { return foundationFailure("Invalid SDK run loop", outThrown) }
    defer { RuntimeFoundationRunLoopTickets.shared.cancel(loop: loop) }
    loop.run()
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_runloop_stop")
public func __kk_foundation_runloop_stop(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let pointer = resolveCPointerBox(from: handle),
          let address = UnsafeRawPointer(bitPattern: pointer.address),
          pointer.pointeeTypeID == runtimeStableNominalTypeID(fqName: "platform.CoreFoundation.__CFRunLoop") else { return foundationFailure("Invalid native CFRunLoopRef", outThrown) }
    let cf = Unmanaged<CFRunLoop>.fromOpaque(address).takeUnretainedValue()
    RuntimeFoundationRunLoopTickets.shared.cancel(key: UInt(bitPattern: address))
    CFRunLoopStop(cf)
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_runloop_add_port")
public func __kk_foundation_runloop_add_port(_ handle: Int, _ port: Int, _ mode: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let loop = runtimeForeignResource(handle, as: RunLoop.self), let port = runtimeForeignResource(port, as: Port.self), let mode = runtimeStringFromRaw(mode) else { return foundationFailure("Invalid SDK run loop port", outThrown) }
    loop.add(port, forMode: .init(rawValue: mode))
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_port_create")
public func __kk_foundation_port_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return runtimeForeignResourceCreate(NSMachPort())
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_thread_create")
public func __kk_foundation_thread_create(_ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let callback = RuntimeFoundationCallback(block), runtimeFunctionValueBox(from: block)?.arity == 0 else { return foundationFailure("SDK thread needs Function0", outThrown) }
    let pin = RuntimeForeignCallbackPin(root: callback.capture)
    let thread = Thread {
        withExtendedLifetime(pin) {
            var thrown = 0
            _ = callback.invoke0(thrown: &thrown)
            if thrown != 0 { kk_native_terminateWithUnhandledException(thrown) }
        }
    }
    return runtimeForeignResourceCreate(thread, roots: [UInt(bitPattern: callback.capture)])
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_thread_current")
public func __kk_foundation_thread_current(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    return runtimeForeignResourceCreate(Thread.current)
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_thread_name")
public func __kk_foundation_thread_name(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let thread = runtimeForeignResource(handle, as: Thread.self) else { return foundationFailure("Invalid SDK thread", outThrown) }
    return thread.name.map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_thread_set_name")
public func __kk_foundation_thread_set_name(_ handle: Int, _ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let thread = runtimeForeignResource(handle, as: Thread.self) else { return foundationFailure("Invalid SDK thread", outThrown) }
    thread.name = runtimeStringFromRaw(name)
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_thread_start")
public func __kk_foundation_thread_start(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
    guard let thread = runtimeForeignResource(handle, as: Thread.self) else { return foundationFailure("Invalid SDK thread", outThrown) }
    thread.start()
    return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_pinned_bytes_address")
public func __kk_foundation_pinned_bytes_address(_ pinned: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let pinned = resolveRuntimeHandle(pinned, as: RuntimePinnedBox.self),
          let array = runtimeArrayBox(from: pinned.objectRaw) else { return foundationFailure("Invalid pinned ByteArray", outThrown) }
    let isByteArray = runtimeStorage.withMetadataLock { state in
        state.arrayTypeIDsByPointer[UInt(bitPattern: pinned.objectRaw)]?.contains(runtimeStableNominalTypeID(fqName: "kotlin.ByteArray")) == true
    }
    guard isByteArray, let address = array.nativeByteAddress(at: index) else {
        outThrown?.pointee = runtimeAllocateArrayIndexOutOfBoundsException(message: "Invalid ByteArray address index/type")
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: address),
        pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
}

@_cdecl("__kk_foundation_memcpy")
public func __kk_foundation_memcpy(_ dst: Int, _ src: Int, _ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard length >= 0, let destination = resolveCPointerBox(from: dst), let source = resolveCPointerBox(from: src),
          let d = UnsafeMutableRawPointer(bitPattern: destination.address), let s = UnsafeRawPointer(bitPattern: source.address) else { return foundationFailure("Invalid memcpy pointer/length", outThrown) }
    _ = memcpy(d, s, length)
    return dst
}

@_cdecl("__kk_foundation_memset")
public func __kk_foundation_memset(_ dst: Int, _ value: Int, _ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard length >= 0, let destination = resolveCPointerBox(from: dst), let d = UnsafeMutableRawPointer(bitPattern: destination.address) else { return foundationFailure("Invalid memset pointer/length", outThrown) }
    _ = memset(d, Int32(truncatingIfNeeded: value), length)
    return dst
}

@_cdecl("__kk_foundation_malloc")
public func __kk_foundation_malloc(_ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
guard length >= 0 else { return foundationFailure("malloc size exceeds native capacity", outThrown) }
guard let pointer = malloc(length) else { return runtimeNullSentinelInt }
return registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: pointer), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
}

@_cdecl("__kk_foundation_free")
public func __kk_foundation_free(_ pointer: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
if let box = resolveCPointerBox(from: pointer), let address = UnsafeMutableRawPointer(bitPattern: box.address) { free(address) }
return 0
}

@_cdecl("__kk_foundation_errno")
public func __kk_foundation_errno(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
return Int(errno)
}

@_cdecl("__kk_foundation_strerror")
public func __kk_foundation_strerror(_ code: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
guard let address = strerror(Int32(truncatingIfNeeded: code)) else { return runtimeNullSentinelInt }
return registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: address), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
}

@_cdecl("__kk_foundation_byte_pointer_add")
public func __kk_foundation_byte_pointer_add(_ pointer: Int, _ offset: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
guard let box = resolveCPointerBox(from: pointer),
      box.pointeeTypeID == runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar") || box.pointeeTypeID == runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.UByteVar") else { return foundationFailure("Expected a byte CPointer", outThrown) }
let (address, overflow) = Int(bitPattern: box.address).addingReportingOverflow(offset)
guard !overflow else { return foundationFailure("CPointer byte offset overflow", outThrown) }
return registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: address), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
}

@_cdecl("__kk_foundation_lock_create")
public func __kk_foundation_lock_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
return runtimeForeignResourceCreate(NSRecursiveLock())
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_lock_lock")
public func __kk_foundation_lock_lock(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
guard let lock = runtimeForeignResource(handle, as: NSRecursiveLock.self) else { return foundationFailure("Invalid SDK recursive lock", outThrown) }
lock.lock()
return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_lock_unlock")
public func __kk_foundation_lock_unlock(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
guard let lock = runtimeForeignResource(handle, as: NSRecursiveLock.self) else { return foundationFailure("Invalid SDK recursive lock", outThrown) }
lock.unlock()
return 0
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}

@_cdecl("__kk_foundation_access")
public func __kk_foundation_access(_ path: Int, _ mode: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
guard let path = runtimeStringFromRaw(path) else { errno = EFAULT; return -1 }
return path.withCString { Int(access($0, Int32(truncatingIfNeeded: mode))) }
}

@_cdecl("__kk_foundation_runloop_cf_pointer")
public func __kk_foundation_runloop_cf_pointer(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    #if canImport(Darwin)
guard let loop = runtimeForeignResource(handle, as: RunLoop.self) else { return foundationFailure("Invalid SDK CFRunLoop receiver", outThrown) }
let address = UInt(bitPattern: Unmanaged.passUnretained(loop.getCFRunLoop()).toOpaque())
return registerRuntimeObject(RuntimeCPointerBox(address: address, pointeeTypeID: runtimeStableNominalTypeID(fqName: "platform.CoreFoundation.__CFRunLoop")))
    #else
    return foundationFailure("Apple Foundation requires Darwin", outThrown)
    #endif
}
