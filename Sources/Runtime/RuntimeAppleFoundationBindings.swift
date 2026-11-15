import Foundation
#if canImport(Darwin)
import Darwin
import CoreFoundation
#elseif canImport(Glibc)
import Glibc
#endif

@_cdecl("__kk_foundation_attach")
public func __kk_foundation_attach(_ owner: Int, _ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard runtimeForeignResourceAttach(handle, owner: owner) else {
            runtimeForeignResourceDiscardUnattached(handle)
            try throwFoundationFailure("Foreign SDK lease needs a live, unique Kotlin owner")
        }
        return 0
    }
}

@_cdecl("__kk_foundation_object_create")
public func __kk_foundation_object_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSObject())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_object_kind")
public func __kk_foundation_object_kind(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let object = runtimeForeignResource(handle, as: NSObject.self) else {
            try throwFoundationFailure("Invalid SDK handle")
        }
        switch object {
        case is NSMutableData: return 7
        case is NSData: return 1
        case is NSError: return 2
        case is InputStream: return 3
        case is OutputStream: return 4
        case is RunLoop: return 5
        case is Thread: return 6
        case is NSDate: return 8
        case is DateFormatter: return 9
        case is NSTimeZone: return 10
        case is NSLocale: return 11
        case is UserDefaults: return 12
        case is NSUUID: return 13
        default: return 0
        }
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_object_equals")
public func __kk_foundation_object_equals(_ lhs: Int, _ rhs: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let a = runtimeForeignResource(lhs, as: NSObject.self),
              let b = runtimeForeignResource(rhs, as: NSObject.self) else {
            try throwFoundationFailure("Invalid SDK equality receiver")
        }
        return a.isEqual(b) ? 1 : 0
    }
}

@_cdecl("__kk_foundation_object_hash")
public func __kk_foundation_object_hash(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let object = runtimeForeignResource(handle, as: NSObject.self) else { try throwFoundationFailure("Invalid SDK hash receiver") }
        return Int(Int32(truncatingIfNeeded: object.hash))
    }
}

@_cdecl("__kk_foundation_data_create")
public func __kk_foundation_data_create(_ bytes: Int, _ length: Int, _ noCopy: Int, _ freeWhenDone: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard length >= 0 else { try throwFoundationFailure("NSData length exceeds Int.max") }
        let address = resolveCPointerBox(from: bytes)?.address ?? 0
        let pointer = UnsafeMutableRawPointer(bitPattern: address)
        guard length == 0 || pointer != nil else { try throwFoundationFailure("Null NSData bytes") }
        if noCopy != 0 {
            if let pointer { return runtimeForeignResourceCreate(NSData(bytesNoCopy: pointer, length: length, freeWhenDone: freeWhenDone != 0)) }
            return runtimeForeignResourceCreate(NSData())
        }
        return runtimeForeignResourceCreate(NSData(bytes: pointer, length: length))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_mutable_data_create")
public func __kk_foundation_mutable_data_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSMutableData())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_data_base64")
public func __kk_foundation_data_base64(_ text: Int, _ options: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let text = runtimeStringFromRaw(text), let data = NSData(base64Encoded: text, options: .init(rawValue: UInt(bitPattern: options))) else { return runtimeNullSentinelInt }
        return kk_box_long_nonnull(runtimeForeignResourceCreate(data))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_data_length")
public func __kk_foundation_data_length(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(handle, as: NSData.self) else { try throwFoundationFailure("Invalid NSData") }
        return data.length
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_data_bytes")
public func __kk_foundation_data_bytes(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(handle, as: NSData.self) else { try throwFoundationFailure("Invalid NSData") }
        return registerRuntimeCPointer(RuntimeCPointerBox(address: UInt(bitPattern: data.bytes),
            pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_mutable_data_append")
public func __kk_foundation_mutable_data_append(_ handle: Int, _ bytes: Int, _ length: Int,
                                               _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard length >= 0, let data = runtimeForeignResource(handle, as: NSMutableData.self) else {
            try throwFoundationFailure("Invalid NSMutableData append")
        }
        let address = resolveCPointerBox(from: bytes)?.address ?? 0
        guard length == 0 || address != 0 else {
            try throwFoundationFailure("Invalid NSMutableData bytes")
        }
        if length > 0 {
            guard let pointer = UnsafeRawPointer(bitPattern: address) else {
                try throwFoundationFailure("Invalid NSMutableData bytes")
            }
            data.append(pointer, length: length)
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_mutable_data_create_length")
public func __kk_foundation_mutable_data_create_length(_ length: Int,
                                                       _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard length >= 0 else {
            try throwFoundationFailure("Invalid NSMutableData length")
        }
        guard let data = NSMutableData(length: length) else {
            return runtimeNullSentinelInt
        }
        return kk_box_long_nonnull(runtimeForeignResourceCreate(data))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

#if canImport(Darwin)
/// NSDataCompressionAlgorithm raw values from NSData.h (NS_ENUM(NSInteger)).
private func runtimeFoundationCompressionAlgorithm(_ raw: Int) -> NSData.CompressionAlgorithm? {
    switch raw {
    case 0: return .lzfse
    case 1: return .lz4
    case 2: return .lzma
    case 3: return .zlib
    default: return nil
    }
}
#endif

@_cdecl("__kk_foundation_data_compressed")
public func __kk_foundation_data_compressed(_ handle: Int, _ algorithm: Int,
                                            _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(handle, as: NSData.self) else {
            try throwFoundationFailure("Invalid NSData")
        }
        guard let algorithm = runtimeFoundationCompressionAlgorithm(algorithm) else {
            try throwFoundationFailure("Unknown NSDataCompressionAlgorithm")
        }
        do {
            let compressed = try data.compressed(using: algorithm)
            return kk_box_long_nonnull(runtimeForeignResourceCreate(compressed as NSData))
        } catch {
            return runtimeNullSentinelInt
        }
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_data_decompressed")
public func __kk_foundation_data_decompressed(_ handle: Int, _ algorithm: Int,
                                              _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(handle, as: NSData.self) else {
            try throwFoundationFailure("Invalid NSData")
        }
        guard let algorithm = runtimeFoundationCompressionAlgorithm(algorithm) else {
            try throwFoundationFailure("Unknown NSDataCompressionAlgorithm")
        }
        do {
            let decompressed = try data.decompressed(using: algorithm)
            return kk_box_long_nonnull(runtimeForeignResourceCreate(decompressed as NSData))
        } catch {
            return runtimeNullSentinelInt
        }
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_string_data_using_encoding")
public func __kk_foundation_string_data_using_encoding(_ textRaw: Int, _ encoding: Int,
                                                       _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let text = runtimeStringFromRaw(textRaw) else {
            try throwFoundationFailure("Invalid Foundation string")
        }
        guard let data = (text as NSString).data(using: UInt(truncatingIfNeeded: encoding),
                                                  allowLossyConversion: false) else {
            return runtimeNullSentinelInt
        }
        return kk_box_long_nonnull(runtimeForeignResourceCreate(data as NSData))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_string_from_data")
public func __kk_foundation_string_from_data(_ handle: Int, _ encoding: Int,
                                             _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(handle, as: NSData.self) else {
            try throwFoundationFailure("Invalid Foundation data")
        }
        guard let text = NSString(data: data as Data, encoding: UInt(truncatingIfNeeded: encoding)) else {
            return runtimeNullSentinelInt
        }
        return runtimeMakeStringRaw(text as String)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_error_create")
public func __kk_foundation_error_create(_ domain: Int, _ code: Int, _ description: Int, _ underlying: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let domain = runtimeStringFromRaw(domain) else { try throwFoundationFailure("Invalid NSError domain") }
        var info: [String: Any] = [:]
        if let description = runtimeStringFromRaw(description) { info[NSLocalizedDescriptionKey] = description }
        if underlying != 0 && underlying != runtimeNullSentinelInt { info[NSUnderlyingErrorKey] = RuntimeFoundationKotlinError(underlying) }
        return runtimeForeignResourceCreate(NSError(domain: domain, code: code, userInfo: info))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_error_description")
public func __kk_foundation_error_description(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let error = runtimeForeignResource(handle, as: NSError.self) else { try throwFoundationFailure("Invalid NSError") }
        return runtimeMakeStringRaw(error.localizedDescription)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_url_file")
public func __kk_foundation_url_file(_ path: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let path = runtimeStringFromRaw(path) else { try throwFoundationFailure("Invalid SDK URL path") }
        return runtimeForeignResourceCreate(NSURL(fileURLWithPath: path))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_input_create")
public func __kk_foundation_input_create(_ data: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let data = runtimeForeignResource(data, as: NSData.self) else { try throwFoundationFailure("Invalid input NSData") }
        return runtimeForeignResourceCreate(InputStream(data: data as Data))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_input_url")
public func __kk_foundation_input_url(_ url: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let url = runtimeForeignResource(url, as: NSURL.self), let stream = InputStream(url: url as URL) else { try throwFoundationFailure("Cannot create SDK input stream") }
        return runtimeForeignResourceCreate(stream)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_output_create")
public func __kk_foundation_output_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(OutputStream.toMemory())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_stream_call")
public func __kk_foundation_stream_call(_ handle: Int, _ operation: Int, _ arg1: Int, _ arg2: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return foundationStreamCall(handle, operation, arg1, arg2, outThrown)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_stream_install")
public func __kk_foundation_stream_install(_ handle: Int, _ block: Int, _ input: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let callback = RuntimeFoundationCallback(block),
              runtimeFunctionValueBox(from: block)?.arity == 3 else { try throwFoundationFailure("SDK stream needs a materialized Function3") }
        let dispatch = RuntimeFoundationStreamDispatch(callback)
        let stream: Stream = input != 0 ? RuntimeFoundationInputStream(dispatch) : RuntimeFoundationOutputStream(dispatch)
        let old = runtimeStorage.withGCLock { state -> RuntimeForeignResourceLease? in
            guard let old = state.foreignResources[handle], old.owner != nil else { return nil }
            let replacement = RuntimeForeignResourceLease(value: stream, dependentRoots: callback.rootKeys)
            replacement.owner = old.owner
            state.foreignResources[handle] = replacement
            return old
        }
        guard old != nil else { try throwFoundationFailure("SDK stream override needs attached owner") }
        withExtendedLifetime(old) {}
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_stream_delegate")
public func __kk_foundation_stream_delegate(_ handle: Int, _ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let stream = runtimeForeignResource(handle, as: Stream.self) else { try throwFoundationFailure("Invalid SDK stream") }
        var proxy: RuntimeFoundationStreamDelegate?
        if block != 0 && block != runtimeNullSentinelInt {
            guard let callback = RuntimeFoundationCallback(block), runtimeFunctionValueBox(from: block)?.arity == 1 else { try throwFoundationFailure("SDK delegate needs Function1") }
            proxy = RuntimeFoundationStreamDelegate(callback)
        }
        let old = runtimeStorage.withGCLock { state -> [AnyObject] in
            guard let lease = state.foreignResources[handle] else { return [] }
            let old = lease.attachments
            lease.attachments = proxy.map { [$0] } ?? []
            lease.attachmentRoots = proxy.map { $0.callback.rootKeys } ?? []
            return old
        }
        stream.delegate = proxy
        withExtendedLifetime(old) {}
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_stream_event")
public func __kk_foundation_stream_event(_ handle: Int, _ event: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let stream = runtimeForeignResource(handle, as: Stream.self) else { try throwFoundationFailure("Invalid SDK stream event receiver") }
        stream.delegate?.stream?(stream, handle: .init(rawValue: UInt(bitPattern: event)))
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_runloop_current")
public func __kk_foundation_runloop_current(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(RunLoop.current)
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_runloop_perform")
public func __kk_foundation_runloop_perform(_ handle: Int, _ modes: Int, _ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let loop = runtimeForeignResource(handle, as: RunLoop.self),
              let modes = runtimeArrayBox(from: modes), let callback = RuntimeFoundationCallback(block),
              runtimeFunctionValueBox(from: block)?.arity == 0 else { try throwFoundationFailure("Invalid SDK run loop block/modes") }
        let names = modes.elements.compactMap(runtimeStringFromRaw)
        guard names.count == modes.count else { try throwFoundationFailure("Invalid SDK run loop mode") }
        let ticket = RuntimeFoundationRunLoopTicket(callback)
        RuntimeFoundationRunLoopTickets.shared.add(ticket, loop: loop)
        // perform runs the block on `loop` itself, so RunLoop.current resolves to the same
        // CFRunLoop key without capturing the non-Sendable RunLoop (or retaining it).
        loop.perform(inModes: names.map { .init(rawValue: $0) }) {
            ticket.invoke()
            RuntimeFoundationRunLoopTickets.shared.finish(ticket, loop: .current)
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_runloop_run")
public func __kk_foundation_runloop_run(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let loop = runtimeForeignResource(handle, as: RunLoop.self) else { try throwFoundationFailure("Invalid SDK run loop") }
        RuntimeFoundationRunLoopTickets.shared.beginRun(loop: loop)
        defer { RuntimeFoundationRunLoopTickets.shared.cancel(loop: loop) }
        while !RuntimeFoundationRunLoopTickets.shared.isStopped(loop: loop) {
            let result = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, false)
            runtimeGCSafepoints.pollIfEnrolled()
            if result == .finished || result == .stopped {
                break
            }
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_runloop_stop")
public func __kk_foundation_runloop_stop(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let pointer = resolveCPointerBox(from: handle),
              let address = UnsafeRawPointer(bitPattern: pointer.address),
              pointer.pointeeTypeID == runtimeStableNominalTypeID(fqName: "platform.CoreFoundation.__CFRunLoop") else { try throwFoundationFailure("Invalid native CFRunLoopRef") }
        let cf = Unmanaged<CFRunLoop>.fromOpaque(address).takeUnretainedValue()
        RuntimeFoundationRunLoopTickets.shared.markStopped(key: UInt(bitPattern: address))
        CFRunLoopStop(cf)
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_runloop_add_port")
public func __kk_foundation_runloop_add_port(_ handle: Int, _ port: Int, _ mode: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let loop = runtimeForeignResource(handle, as: RunLoop.self), let port = runtimeForeignResource(port, as: Port.self), let mode = runtimeStringFromRaw(mode) else { try throwFoundationFailure("Invalid SDK run loop port") }
        loop.add(port, forMode: .init(rawValue: mode))
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_port_create")
public func __kk_foundation_port_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSMachPort())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

/// Pins the Kotlin callback only once the thread starts, so a thread that is
/// created but never started does not keep its block alive.
private final class RuntimeFoundationThreadBody: @unchecked Sendable {
    private let lock = NSLock()
    private let callback: RuntimeFoundationCallback
    private var queuedRoots: RuntimeQueuedGCRoots?
    private var started = false

    init(callback: RuntimeFoundationCallback) {
        self.callback = callback
    }

    /// False when the thread was already started.
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return false }
        started = true
        queuedRoots = RuntimeQueuedGCRoots(callback.roots)
        return true
    }

    func run() {
        defer {
            lock.lock()
            let roots = queuedRoots
            queuedRoots = nil
            lock.unlock()
            roots?.finish()
        }
        var thrown = 0
        _ = callback.invoke0(thrown: &thrown)
        if thrown != 0 {
            kk_native_terminateWithUnhandledException(thrown)
        }
    }
}

#if canImport(Darwin)
private final class RuntimeFoundationThread: Thread, @unchecked Sendable {
    private let body: RuntimeFoundationThreadBody

    init(callback: RuntimeFoundationCallback) {
        body = RuntimeFoundationThreadBody(callback: callback)
        super.init()
    }

    override func start() {
        guard body.begin() else { return }
        super.start()
    }

    override func main() {
        body.run()
    }
}
#else
// swift-corelibs-foundation's Thread cannot be subclassed from another module,
// so off Darwin the body rides beside a block-based Thread. java.lang.Thread,
// Timer and Executors are built over NSThread and need it on Linux too.
private let runtimeFoundationThreadBodiesLock = NSLock()
nonisolated(unsafe) private var runtimeFoundationThreadBodies: [ObjectIdentifier: RuntimeFoundationThreadBody] = [:]
nonisolated(unsafe) private var runtimeFoundationMainThreadNamed = false
#endif

@_cdecl("__kk_foundation_thread_create")
public func __kk_foundation_thread_create(_ block: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let callback = RuntimeFoundationCallback(block), runtimeFunctionValueBox(from: block)?.arity == 0 else { try throwFoundationFailure("SDK thread needs Function0") }
        #if canImport(Darwin)
        let thread = RuntimeFoundationThread(callback: callback)
        #else
        let body = RuntimeFoundationThreadBody(callback: callback)
        let thread = Thread { body.run() }
        runtimeFoundationThreadBodiesLock.withLock {
            runtimeFoundationThreadBodies[ObjectIdentifier(thread)] = body
        }
        #endif
        return runtimeForeignResourceCreate(thread, roots: callback.rootKeys)
    }
}

@_cdecl("__kk_foundation_thread_current")
public func __kk_foundation_thread_current(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        let current = Thread.current
        #if canImport(Darwin)
        if Thread.isMainThread, current.name?.isEmpty != false {
            current.name = "main"
        }
        #else
        // Linux names the main thread after the process, so name it once
        // instead of only when the name is empty.
        if Thread.isMainThread {
            runtimeFoundationThreadBodiesLock.withLock {
                if !runtimeFoundationMainThreadNamed {
                    runtimeFoundationMainThreadNamed = true
                    current.name = "main"
                }
            }
        }
        #endif
        return runtimeForeignResourceCreate(current)
    }
}

@_cdecl("__kk_foundation_thread_name")
public func __kk_foundation_thread_name(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let thread = runtimeForeignResource(handle, as: Thread.self) else { try throwFoundationFailure("Invalid SDK thread") }
        return thread.name.map(runtimeMakeStringRaw) ?? runtimeNullSentinelInt
    }
}

@_cdecl("__kk_foundation_thread_set_name")
public func __kk_foundation_thread_set_name(_ handle: Int, _ name: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let thread = runtimeForeignResource(handle, as: Thread.self) else { try throwFoundationFailure("Invalid SDK thread") }
        thread.name = runtimeStringFromRaw(name)
        return 0
    }
}

@_cdecl("__kk_foundation_thread_start")
public func __kk_foundation_thread_start(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let thread = runtimeForeignResource(handle, as: Thread.self) else { try throwFoundationFailure("Invalid SDK thread") }
        #if !canImport(Darwin)
        // A second start is a no-op like the Darwin override; a thread the runtime
        // did not create has no body.
        let body = runtimeFoundationThreadBodiesLock.withLock {
            runtimeFoundationThreadBodies[ObjectIdentifier(thread)]
        }
        if let body, !body.begin() { return 0 }
        #endif
        thread.start()
        return 0
    }
}

@_cdecl("__kk_foundation_pinned_bytes_address")
public func __kk_foundation_pinned_bytes_address(_ pinned: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let pinned = resolveRuntimeHandle(pinned, as: RuntimePinnedBox.self),
              let array = runtimeArrayBox(from: pinned.objectRaw) else { try throwFoundationFailure("Invalid pinned ByteArray") }
        let isByteArray = runtimeStorage.withMetadataLock { state in
            state.arrayTypeIDsByPointer[UInt(bitPattern: pinned.objectRaw)]?.contains(runtimeStableNominalTypeID(fqName: "kotlin.ByteArray")) == true
        }
        guard isByteArray, let address = array.nativeByteAddress(at: index) else {
            throw RuntimeThrownHandle(runtimeAllocateArrayIndexOutOfBoundsException(message: "Invalid ByteArray address index/type"))
        }
        return registerRuntimeCPointer(RuntimeCPointerBox(address: UInt(bitPattern: address),
            pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
    }
}

@_cdecl("__kk_foundation_memcpy")
public func __kk_foundation_memcpy(_ dst: Int, _ src: Int, _ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard length >= 0, let destination = resolveCPointerBox(from: dst), let source = resolveCPointerBox(from: src),
              let d = UnsafeMutableRawPointer(bitPattern: destination.address), let s = UnsafeRawPointer(bitPattern: source.address) else { try throwFoundationFailure("Invalid memcpy pointer/length") }
        _ = memcpy(d, s, length)
        return dst
    }
}

@_cdecl("__kk_foundation_memset")
public func __kk_foundation_memset(_ dst: Int, _ value: Int, _ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard length >= 0, let destination = resolveCPointerBox(from: dst), let d = UnsafeMutableRawPointer(bitPattern: destination.address) else { try throwFoundationFailure("Invalid memset pointer/length") }
        _ = memset(d, Int32(truncatingIfNeeded: value), length)
        return dst
    }
}

@_cdecl("__kk_foundation_malloc")
public func __kk_foundation_malloc(_ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard length >= 0 else { try throwFoundationFailure("malloc size exceeds native capacity") }
        guard let pointer = malloc(length) else { return runtimeNullSentinelInt }
        return registerRuntimeCPointer(RuntimeCPointerBox(address: UInt(bitPattern: pointer), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
    }
}

@_cdecl("__kk_foundation_free")
public func __kk_foundation_free(_ pointer: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        if let box = resolveCPointerBox(from: pointer), let address = UnsafeMutableRawPointer(bitPattern: box.address) { free(address) }
        return 0
    }
}

@_cdecl("__kk_foundation_errno")
public func __kk_foundation_errno(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        return Int(errno)
    }
}

@_cdecl("__kk_foundation_strerror")
public func __kk_foundation_strerror(_ code: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let address = strerror(Int32(truncatingIfNeeded: code)) else { return runtimeNullSentinelInt }
        return registerRuntimeCPointer(RuntimeCPointerBox(address: UInt(bitPattern: address), pointeeTypeID: runtimeStableNominalTypeID(fqName: "kotlinx.cinterop.ByteVar")))
    }
}

@_cdecl("__kk_foundation_byte_pointer_add")
public func __kk_foundation_byte_pointer_add(_ pointer: Int, _ offset: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let box = resolveCPointerBox(from: pointer),
              let kind = runtimeCInteropVarKind(forNominalTypeID: box.pointeeTypeID),
              kind == .int8 || kind == .uint8 else { try throwFoundationFailure("Expected a byte CPointer") }
        let (address, overflow) = Int(bitPattern: box.address).addingReportingOverflow(offset)
        guard !overflow else { try throwFoundationFailure("CPointer byte offset overflow") }
        return registerRuntimeCPointer(RuntimeCPointerBox(address: UInt(bitPattern: address), pointeeTypeID: box.pointeeTypeID))
    }
}

@_cdecl("__kk_foundation_lock_create")
public func __kk_foundation_lock_create(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        return runtimeForeignResourceCreate(NSRecursiveLock())
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_lock_lock")
public func __kk_foundation_lock_lock(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let lock = runtimeForeignResource(handle, as: NSRecursiveLock.self) else { try throwFoundationFailure("Invalid SDK recursive lock") }
        while !lock.try() {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            if !gcBlocking {
                lock.lock()
                break
            }
            Thread.sleep(forTimeInterval: 0.001)
            runtimeGCSafepoints.endBlocking()
        }
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_lock_unlock")
public func __kk_foundation_lock_unlock(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let lock = runtimeForeignResource(handle, as: NSRecursiveLock.self) else { try throwFoundationFailure("Invalid SDK recursive lock") }
        lock.unlock()
        return 0
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}

@_cdecl("__kk_foundation_access")
public func __kk_foundation_access(_ path: Int, _ mode: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        guard let path = runtimeStringFromRaw(path) else { errno = EFAULT; return -1 }
        return path.withCString { Int(access($0, Int32(truncatingIfNeeded: mode))) }
    }
}

@_cdecl("__kk_foundation_runloop_cf_pointer")
public func __kk_foundation_runloop_cf_pointer(_ handle: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown, defaultOnFailure: runtimeNullSentinelInt) {
        #if canImport(Darwin)
        guard let loop = runtimeForeignResource(handle, as: RunLoop.self) else { try throwFoundationFailure("Invalid SDK CFRunLoop receiver") }
        let address = UInt(bitPattern: Unmanaged.passUnretained(loop.getCFRunLoop()).toOpaque())
        return registerRuntimeCPointer(RuntimeCPointerBox(address: address, pointeeTypeID: runtimeStableNominalTypeID(fqName: "platform.CoreFoundation.__CFRunLoop")))
        #else
        try throwFoundationFailure("Apple Foundation requires Darwin")
        #endif
    }
}
