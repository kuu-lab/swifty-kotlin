import Dispatch
import Foundation
import RuntimeABI

#if os(macOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

func runtimeCurrentPlatformThreadID() -> UInt64 {
#if os(macOS)
    return UInt64(pthread_mach_thread_np(pthread_self()))
#elseif os(Linux)
    return UInt64(pthread_self())
#else
    return 0
#endif
}


func runtimeCurrentStackTraceAddresses() -> [Int] {
    Thread.callStackReturnAddresses.map { Int(truncating: $0) }
}


/// In the KSwiftK ABI, pointer types are represented as boxed `Int` values that
/// carry the machine-word address. `pointeeTypeID` is the nominal typeID of T
/// (0 = opaque/untyped), used by `pointed`, `get`, and `reinterpret` to select
/// the pointee's C layout.
final class RuntimeCPointerBox: @unchecked Sendable {
    let address: UInt
    let pointeeTypeID: Int64
    init(address: UInt, pointeeTypeID: Int64 = 0) {
        self.address = address
        self.pointeeTypeID = pointeeTypeID
    }
}

final class RuntimeCOpaquePointerBox: @unchecked Sendable {
    let address: UInt
    init(address: UInt) {
        self.address = address
    }
}

@_cdecl("kk_cpointer_new")
public func kk_cpointer_new(_ address: Int) -> Int {
    registerRuntimeObject(RuntimeCPointerBox(address: UInt(bitPattern: address)))
}

func resolveCPointerBox(from handle: Int) -> RuntimeCPointerBox? {
    guard handle != 0, handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    let key = UInt(bitPattern: ptr)
    let isRegistered = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(key)
    }
    guard isRegistered else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCPointerBox.self)
}

@_cdecl("kk_cpointer_address")
public func kk_cpointer_address(_ handle: Int) -> Int {
    guard let box = resolveCPointerBox(from: handle) else { return 0 }
    return Int(bitPattern: box.address)
}

@_cdecl("kk_cpointer_toLong")
public func kk_cpointer_toLong(_ handle: Int) -> Int {
    kk_cpointer_address(handle)
}

@_cdecl("kk_cpointer_toKStringFromUtf32")
public func kk_cpointer_toKStringFromUtf32(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else { return 0 }
    guard let box = tryCast(ptr, to: RuntimeCPointerBox.self) else { return 0 }
    guard box.address != 0, let utf32 = UnsafePointer<Int32>(bitPattern: box.address) else { return 0 }
    var result = ""
    var index = 0
    while utf32[index] != 0 {
        let codePoint = UInt32(bitPattern: utf32[index])
        if let scalar = Unicode.Scalar(codePoint) {
            result.unicodeScalars.append(scalar)
        }
        index += 1
    }
    return runtimeMakeStringRaw(KotlinStringSurrogateEncoding.encode(result))
}

@_cdecl("kk_cpointer_toKStringFromUtf16")
public func kk_cpointer_toKStringFromUtf16(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else { return 0 }
    guard let box = tryCast(ptr, to: RuntimeCPointerBox.self) else { return 0 }
    guard box.address != 0, let utf16 = UnsafePointer<UInt16>(bitPattern: box.address) else { return 0 }
    var units: [UInt16] = []
    var index = 0
    while utf16[index] != 0 {
        units.append(utf16[index])
        index += 1
    }
    return registerRuntimeObject(RuntimeStringBox(runtimeKotlinStringFromUTF16CodeUnits(units)))
}

@_cdecl("kk_copaque_pointer_new")
public func kk_copaque_pointer_new(_ address: Int) -> Int {
    registerRuntimeObject(RuntimeCOpaquePointerBox(address: UInt(bitPattern: address)))
}

@_cdecl("kk_copaque_pointer_address")
public func kk_copaque_pointer_address(_ handle: Int) -> Int {
    // A null `COpaquePointer?` arrives as the runtime null sentinel, not 0.
    guard handle != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: handle)
    else {
        return 0
    }
    guard let box = tryCast(ptr, to: RuntimeCOpaquePointerBox.self) else {
        return 0
    }
    return Int(bitPattern: box.address)
}

@_cdecl("kk_native_identityHashCode")
public func kk_native_identityHashCode(_ objectRaw: Int) -> Int {
    guard objectRaw != 0, objectRaw != runtimeNullSentinelInt else {
        return 0
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: objectRaw) else {
        return objectRaw
    }

    let key = UInt(bitPattern: ptr)
    let isKnownRuntimeObject = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(key) || state.heapObjects[key] != nil
    }
    guard isKnownRuntimeObject else {
        return objectRaw
    }

    var mixed = UInt64(key)
    mixed ^= mixed >> 33
    mixed &*= 0xff51_afd7_ed55_8ccd
    mixed ^= mixed >> 33
    return Int(truncatingIfNeeded: mixed)
}

@_cdecl("kk_native_getStackTraceAddresses")
public func kk_native_getStackTraceAddresses(_ throwableRaw: Int) -> Int {
    let addresses: [Int]
    if let pointer = UnsafeMutableRawPointer(bitPattern: throwableRaw),
       runtimeStorage.withGCLock({ state in
           state.objectPointers.contains(UInt(bitPattern: pointer))
       })
    {
        if let throwable = tryCast(pointer, to: RuntimeThrowableBox.self) {
            addresses = throwable.writableStackTrace ? throwable.stackTraceAddresses : []
        } else if let throwable = tryCast(pointer, to: RuntimeObjectBox.self) {
            addresses = throwable.throwableWritableStackTrace
                ? throwable.throwableStackTraceAddresses ?? []
                : []
        } else {
            addresses = []
        }
    } else {
        addresses = []
    }
    return registerRuntimeObject(RuntimeListBox(elements: addresses))
}

@_cdecl("__kk_throwable_captureStackTrace")
public func __kk_throwable_captureStackTrace(_ throwableRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: throwableRaw),
          runtimeStorage.withGCLock({ state in
              state.objectPointers.contains(UInt(bitPattern: pointer))
          }),
          let object = tryCast(pointer, to: RuntimeObjectBox.self)
    else {
        return throwableRaw
    }
    guard object.throwableWritableStackTrace else {
        object.throwableStackTraceAddresses = []
        return throwableRaw
    }
    if object.throwableStackTraceAddresses == nil {
        object.throwableStackTraceAddresses = runtimeCurrentStackTraceAddresses()
    }
    return throwableRaw
}

private final class RuntimeUnhandledExceptionHookRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var hookRaw: Int = runtimeNullSentinelInt

    func get() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return hookRaw
    }

    func set(_ raw: Int) -> Int {
        lock.lock()
        let previous = hookRaw
        hookRaw = raw == 0 || raw == runtimeNullSentinelInt ? runtimeNullSentinelInt : raw
        lock.unlock()
        return previous
    }
}

private let runtimeUnhandledExceptionHookRegistry = RuntimeUnhandledExceptionHookRegistry()

@_cdecl("kk_native_getUnhandledExceptionHook")
public func kk_native_getUnhandledExceptionHook() -> Int {
    runtimeUnhandledExceptionHookRegistry.get()
}

@_cdecl("kk_native_setUnhandledExceptionHook")
public func kk_native_setUnhandledExceptionHook(_ hookRaw: Int) -> Int {
    runtimeUnhandledExceptionHookRegistry.set(hookRaw)
}

@_cdecl("kk_native_processUnhandledException")
public func kk_native_processUnhandledException(
    _ throwableRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let hookRaw = runtimeUnhandledExceptionHookRegistry.get()
    guard hookRaw != 0, hookRaw != runtimeNullSentinelInt else {
        return 0
    }
    _ = kk_function_invoke(hookRaw, throwableRaw, outThrown)
    return 0
}

@_cdecl("kk_native_terminateWithUnhandledException")
public func kk_native_terminateWithUnhandledException(_ throwableRaw: Int) -> Never {
    _ = kk_native_processUnhandledException(throwableRaw, nil)
    runtimeStructuredPanic("Unhandled Kotlin exception: \(throwableRaw)")
}


/// ImmutableBlob has the same element layout as ByteArray. The source-backed
/// factory receives the raw Short vararg array; each element is truncated to
/// one byte just as Kotlin/Native's ImmutableBlob constructor does.
@_cdecl("__kk_immutable_blob_of")
public func kk_immutable_blob_of(_ elementsRaw: Int, _: Int) -> Int {
    guard let elements = runtimeArrayBox(from: elementsRaw) else {
        return 0
    }
    let blob = RuntimeArrayBox(length: elements.count)
    for index in 0..<elements.count {
        blob[index] = Int(Int8(truncatingIfNeeded: elements[index]))
    }
    let raw = registerRuntimeObject(blob)
    runtimeRegisterObjectType(
        rawValue: raw,
        classID: runtimeStableNominalTypeID(fqName: "kotlin.native.ImmutableBlob")
    )
    return raw
}

@inline(__always)
private func runtimeNativeByteArrayLoadUnsigned(
    _ arrayRaw: Int,
    _ index: Int,
    byteCount: Int,
    functionName: String
) -> UInt64 {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    guard index >= 0, index <= array.count, byteCount >= 0, byteCount <= array.count - index else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: index out of bounds in \(functionName)")
    }

    var value: UInt64 = 0
    for byteOffset in 0..<byteCount {
        let byte = UInt8(truncatingIfNeeded: array[index + byteOffset])
        value |= UInt64(byte) << UInt64(byteOffset * 8)
    }
    return value
}

@inline(__always)
private func runtimeNativeByteArrayStoreUnsigned(
    _ arrayRaw: Int,
    _ index: Int,
    value: UInt64,
    byteCount: Int,
    functionName: String
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in \(functionName)")
    }
    guard index >= 0, index <= array.count, byteCount >= 0, byteCount <= array.count - index else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: index out of bounds in \(functionName)")
    }

    for byteOffset in 0..<byteCount {
        let byte = UInt8(truncatingIfNeeded: value >> UInt64(byteOffset * 8))
        array[index + byteOffset] = Int(Int8(bitPattern: byte))
    }
    return 0
}

@_cdecl("kk_native_byteArray_getByteAt")
public func kk_native_byteArray_getByteAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 1,
        functionName: "kk_native_byteArray_getByteAt"
    )
    return Int(Int8(bitPattern: UInt8(truncatingIfNeeded: value)))
}

@_cdecl("kk_native_byteArray_getShortAt")
public func kk_native_byteArray_getShortAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 2,
        functionName: "kk_native_byteArray_getShortAt"
    )
    return Int(Int16(bitPattern: UInt16(truncatingIfNeeded: value)))
}

@_cdecl("kk_native_byteArray_getIntAt")
public func kk_native_byteArray_getIntAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 4,
        functionName: "kk_native_byteArray_getIntAt"
    )
    return Int(Int32(bitPattern: UInt32(truncatingIfNeeded: value)))
}

@_cdecl("kk_native_byteArray_getLongAt")
public func kk_native_byteArray_getLongAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 8,
        functionName: "kk_native_byteArray_getLongAt"
    )
    return Int(Int64(bitPattern: value))
}

@_cdecl("kk_native_byteArray_getUByteAt")
public func kk_native_byteArray_getUByteAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 1,
        functionName: "kk_native_byteArray_getUByteAt"
    )
    return Int(UInt8(truncatingIfNeeded: value))
}

@_cdecl("kk_native_byteArray_getUShortAt")
public func kk_native_byteArray_getUShortAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 2,
        functionName: "kk_native_byteArray_getUShortAt"
    )
    return Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_native_byteArray_getUIntAt")
public func kk_native_byteArray_getUIntAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 4,
        functionName: "kk_native_byteArray_getUIntAt"
    )
    return Int(UInt32(truncatingIfNeeded: value))
}

@_cdecl("kk_native_byteArray_getULongAt")
public func kk_native_byteArray_getULongAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 8,
        functionName: "kk_native_byteArray_getULongAt"
    )
    return Int(truncatingIfNeeded: value)
}

@_cdecl("kk_native_byteArray_getCharAt")
public func kk_native_byteArray_getCharAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 2,
        functionName: "kk_native_byteArray_getCharAt"
    )
    return Int(UInt16(truncatingIfNeeded: value))
}

@_cdecl("kk_native_byteArray_getFloatAt")
public func kk_native_byteArray_getFloatAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 4,
        functionName: "kk_native_byteArray_getFloatAt"
    )
    let bits = UInt32(truncatingIfNeeded: value)
    return kk_float_to_bits(Float(bitPattern: bits))
}

@_cdecl("kk_native_byteArray_getDoubleAt")
public func kk_native_byteArray_getDoubleAt(_ arrayRaw: Int, _ index: Int) -> Int {
    let value = runtimeNativeByteArrayLoadUnsigned(
        arrayRaw,
        index,
        byteCount: 8,
        functionName: "kk_native_byteArray_getDoubleAt"
    )
    return kk_double_to_bits(Double(bitPattern: value))
}

@_cdecl("kk_native_byteArray_setByteAt")
public func kk_native_byteArray_setByteAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt8(truncatingIfNeeded: value)),
        byteCount: 1,
        functionName: "kk_native_byteArray_setByteAt"
    )
}

@_cdecl("kk_native_byteArray_setShortAt")
public func kk_native_byteArray_setShortAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt16(truncatingIfNeeded: value)),
        byteCount: 2,
        functionName: "kk_native_byteArray_setShortAt"
    )
}

@_cdecl("kk_native_byteArray_setIntAt")
public func kk_native_byteArray_setIntAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt32(truncatingIfNeeded: value)),
        byteCount: 4,
        functionName: "kk_native_byteArray_setIntAt"
    )
}

@_cdecl("kk_native_byteArray_setLongAt")
public func kk_native_byteArray_setLongAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(bitPattern: Int64(value)),
        byteCount: 8,
        functionName: "kk_native_byteArray_setLongAt"
    )
}

@_cdecl("kk_native_byteArray_setUByteAt")
public func kk_native_byteArray_setUByteAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt8(truncatingIfNeeded: value)),
        byteCount: 1,
        functionName: "kk_native_byteArray_setUByteAt"
    )
}

@_cdecl("kk_native_byteArray_setUShortAt")
public func kk_native_byteArray_setUShortAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt16(truncatingIfNeeded: value)),
        byteCount: 2,
        functionName: "kk_native_byteArray_setUShortAt"
    )
}

@_cdecl("kk_native_byteArray_setUIntAt")
public func kk_native_byteArray_setUIntAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt32(truncatingIfNeeded: value)),
        byteCount: 4,
        functionName: "kk_native_byteArray_setUIntAt"
    )
}

@_cdecl("kk_native_byteArray_setULongAt")
public func kk_native_byteArray_setULongAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(bitPattern: Int64(value)),
        byteCount: 8,
        functionName: "kk_native_byteArray_setULongAt"
    )
}

@_cdecl("kk_native_byteArray_setCharAt")
public func kk_native_byteArray_setCharAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt16(truncatingIfNeeded: value)),
        byteCount: 2,
        functionName: "kk_native_byteArray_setCharAt"
    )
}

@_cdecl("kk_native_byteArray_setFloatAt")
public func kk_native_byteArray_setFloatAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(UInt32(truncatingIfNeeded: value)),
        byteCount: 4,
        functionName: "kk_native_byteArray_setFloatAt"
    )
}

@_cdecl("kk_native_byteArray_setDoubleAt")
public func kk_native_byteArray_setDoubleAt(_ arrayRaw: Int, _ index: Int, _ value: Int) -> Int {
    return runtimeNativeByteArrayStoreUnsigned(
        arrayRaw,
        index,
        value: UInt64(bitPattern: Int64(value)),
        byteCount: 8,
        functionName: "kk_native_byteArray_setDoubleAt"
    )
}


/// Holds a copy of the ByteArray contents in a C-layout buffer allocated on
/// the unmanaged heap. The buffer is freed when this box is deallocated by
/// the KSwiftK GC. The raw address can be wrapped in a `RuntimeCPointerBox`
/// to satisfy `CValuesRef.getPointer(scope)` at the call site.
final class RuntimeCValuesBox: @unchecked Sendable {
    let storage: UnsafeMutableBufferPointer<Int8>

    init(bytes: [Int]) {
        let count = bytes.count
        storage = UnsafeMutableBufferPointer<Int8>.allocate(capacity: max(1, count))
        for (i, b) in bytes.enumerated() {
            storage[i] = Int8(truncatingIfNeeded: b)
        }
    }

    init(ulongs: [Int]) {
        let count = ulongs.count
        storage = UnsafeMutableBufferPointer<Int8>.allocate(capacity: max(1, count * 8))
        for (i, elem) in ulongs.enumerated() {
            withUnsafeBytes(of: UInt64(bitPattern: Int64(elem))) { raw in
                for j in 0..<8 {
                    storage[i * 8 + j] = Int8(bitPattern: raw[j])
                }
            }
        }
    }

    init(uints: [Int]) {
        let count = uints.count
        storage = UnsafeMutableBufferPointer<Int8>.allocate(capacity: max(1, count * 4))
        for (i, elem) in uints.enumerated() {
            withUnsafeBytes(of: UInt32(truncatingIfNeeded: elem)) { raw in
                for j in 0..<4 {
                    storage[i * 4 + j] = Int8(bitPattern: raw[j])
                }
            }
        }
    }

    deinit {
        storage.deallocate()
    }
}

@_cdecl("kk_byteArray_toCValues")
public func kk_byteArray_toCValues(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_byteArray_toCValues")
    }
    return registerRuntimeObject(RuntimeCValuesBox(bytes: array.elements))
}

@_cdecl("kk_uLongArray_toCValues")
public func kk_uLongArray_toCValues(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uLongArray_toCValues")
    }
    return registerRuntimeObject(RuntimeCValuesBox(ulongs: array.elements))
}

@_cdecl("kk_uIntArray_toCValues")
public func kk_uIntArray_toCValues(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uIntArray_toCValues")
    }
    return registerRuntimeObject(RuntimeCValuesBox(uints: array.elements))
}

@_cdecl("kk_uByteArray_toCValues")
public func kk_uByteArray_toCValues(_ arrayRaw: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid array handle in kk_uByteArray_toCValues")
    }
    return registerRuntimeObject(RuntimeCValuesBox(bytes: array.elements))
}


/// Returns a stable native address for `ImmutableBlob.asCPointer(offset)` /
/// `asUCPointer(offset)` (upstream `Kotlin_ImmutableBlob_asCPointerImpl`).
///
/// RuntimeArrayBox storage is `[RuntimeValue]`, which is not byte-addressable
/// C storage, so the blob's bytes are copied into a `RuntimeCValuesBox`'s
/// unmanaged heap buffer and `baseAddress + offset` is returned. The box is
/// pinned permanently: the escaped address has no release path in this API,
/// and upstream ImmutableBlobs are effectively immortal once exposed as a C
/// pointer.
@_cdecl("__kk_immutable_blob_as_cpointer")
public func __kk_immutable_blob_as_cpointer(_ blobRaw: Int, _ offset: Int) -> Int {
    guard let array = runtimeArrayBox(from: blobRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid ImmutableBlob handle in __kk_immutable_blob_as_cpointer")
    }
    guard offset >= 0 && offset <= array.count else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_immutable_blob_as_cpointer offset \(offset) out of bounds for blob of size \(array.count)")
    }
    let box = RuntimeCValuesBox(bytes: array.elements)
    let boxRaw = registerRuntimeObject(box)
    runtimeStorage.withGCLock { state in
        state.pinnedObjectCounts[UInt(bitPattern: boxRaw), default: 0] += 1
    }
    guard let baseAddress = box.storage.baseAddress else {
        return 0
    }
    return Int(bitPattern: baseAddress) + offset
}


/// Pinning prevents the GC from moving (or collecting) a heap object while
/// the pin is held.  In the KSwiftK stop-the-world mark-sweep GC objects
/// are never moved, so pinning is implemented as a simple reference hold:
/// `GCState.pinnedObjectCounts` keeps a per-target refcount of outstanding
/// pins, and the mark phase roots every target with a non-zero count.
///
/// ABI-005: `unpinned` guards against double-unpin UB.  Once `kk_unpin_object`
/// executes the release path, the flag is set to `true`; any subsequent call
/// with the same handle is a no-op.
final class RuntimePinnedBox: @unchecked Sendable {
    let objectRaw: Int
    private let lock = NSLock()
    private var _unpinned = false

    init(objectRaw: Int) {
        self.objectRaw = objectRaw
    }

    /// Atomically transitions the box from pinned → unpinned.
    /// Returns `true` on the first call (caller must do the release);
    /// returns `false` on any subsequent call (no-op).
    func tryUnpin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_unpinned else { return false }
        _unpinned = true
        return true
    }
}

@_cdecl("kk_pin_object")
public func kk_pin_object(_ objectRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    // Register the object as a GC root so the mark-sweep collector treats it
    // as reachable for as long as the pin is held. Each call returns an
    // independent handle, so the root is a per-target refcount rather than a
    // single membership: unpinning one handle must not unroot the target
    // while sibling pins are still held.
    runtimeStorage.withGCLock { state in
        state.pinnedObjectCounts[UInt(bitPattern: objectRaw), default: 0] += 1
    }
    return registerRuntimeObject(RuntimePinnedBox(objectRaw: objectRaw))
}

@_cdecl("kk_unpin_object")
public func kk_unpin_object(_ pinnedHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pinnedHandle) else {
        return 0
    }
    // The whole handle lifetime protocol — registration check, box cast,
    // double-unpin guard, and root refcount decrement — runs inside one
    // GC-lock critical section. The membership check before tryCast keeps
    // takeUnretainedValue safe (a registered box is still passRetained, and
    // the release path cannot drop it while the lock is held), and bundling
    // the refcount update with the handle checks leaves no window for a
    // concurrent unpin/release to observe intermediate state.
    var shouldReleaseHandle = false
    let objectRaw = runtimeStorage.withGCLock { state -> Int? in
        // ABI-005: guard is not registered at all → silently no-op.
        guard state.objectPointers.contains(UInt(bitPattern: ptr)),
              let box = tryCast(ptr, to: RuntimePinnedBox.self)
        else {
            return nil
        }
        // ABI-005: idempotency guard — second unpin on same handle is a no-op.
        guard box.tryUnpin() else {
            return box.objectRaw
        }
        shouldReleaseHandle = true
        let objectRaw = box.objectRaw
        // Drop this handle's share of the GC root; the target stays rooted
        // until the last independent pin on it is released.
        let key = UInt(bitPattern: objectRaw)
        if let count = state.pinnedObjectCounts[key], count > 1 {
            state.pinnedObjectCounts[key] = count - 1
        } else {
            state.pinnedObjectCounts.removeValue(forKey: key)
        }
        return objectRaw
    }
    guard let objectRaw else {
        return 0
    }
    if shouldReleaseHandle {
        _ = runtimeReleaseObject(pinnedHandle)
    }
    return objectRaw
}

@_cdecl("kk_pinned_get")
public func kk_pinned_get(_ pinnedHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pinnedHandle) else {
        return 0
    }
    // Same atomic handle-lifetime protocol as kk_unpin_object: only a box
    // still registered in objectPointers is safe to takeUnretainedValue on.
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)),
              let box = tryCast(ptr, to: RuntimePinnedBox.self)
        else {
            return 0
        }
        return box.objectRaw
    }
}


/// Runtime backing for `kotlinx.cinterop.StableRef<T>`.
///
/// Same GC-root-pinning mechanism as `Pinned<T>` above (KSwiftK never moves
/// heap objects, so pinning is a reachability hold rather than a real pin),
/// backed by its own per-target refcount table (`stableRefCounts`) because
/// the handle mechanics differ: StableRef handles are COpaquePointer boxes
/// disposed by target address rather than per-handle boxes, and the public
/// contract allows the same target to be wrapped by several independent
/// handles at once (e.g.
/// `kotlin.native.concurrent.Continuation1.invoke` creates a fresh
/// `StableRef` per call while the block's own StableRef stays alive across
/// many calls), and disposing one handle must never unpin a sibling handle
/// to the same object.
///
/// The resulting pointer is boxed through the existing `RuntimeCOpaquePointerBox`
/// (`kk_copaque_pointer_new`/`kk_copaque_pointer_address`) so `StableRef.stablePtr`
/// is a regular `COpaquePointer` value, matching `StableRef.asCPointer()`'s
/// contract of handing back something safe to pass to native code.
@_cdecl("kk_stable_ref_create")
public func kk_stable_ref_create(_ objectRaw: Int) -> Int {
    guard objectRaw != 0 else {
        return 0
    }
    runtimeStorage.withGCLock { state in
        state.stableRefCounts[UInt(bitPattern: objectRaw), default: 0] += 1
    }
    return kk_copaque_pointer_new(objectRaw)
}

@_cdecl("kk_stable_ref_deref")
public func kk_stable_ref_deref(_ pointerHandle: Int) -> Int {
    let objectRaw = kk_copaque_pointer_address(pointerHandle)
    guard objectRaw != 0 else {
        return runtimeNullSentinelInt
    }
    let isLive = runtimeStorage.withGCLock { state in
        (state.stableRefCounts[UInt(bitPattern: objectRaw)] ?? 0) > 0
    }
    // Guards against a COpaquePointer that was never a StableRef (or was
    // already disposed): kk_copaque_pointer_address would otherwise return
    // its raw address unchecked, and `get()`'s `as T` would then fault on
    // garbage instead of throwing a clean ClassCastException.
    guard isLive else {
        return runtimeNullSentinelInt
    }
    return objectRaw
}

@_cdecl("kk_stable_ref_dispose")
public func kk_stable_ref_dispose(_ pointerHandle: Int) -> Int {
    let objectRaw = kk_copaque_pointer_address(pointerHandle)
    guard objectRaw != 0 else {
        return 0
    }
    return runtimeStorage.withGCLock { state in
        let key = UInt(bitPattern: objectRaw)
        guard let count = state.stableRefCounts[key], count > 0 else {
            return 0
        }
        if count == 1 {
            state.stableRefCounts.removeValue(forKey: key)
        } else {
            state.stableRefCounts[key] = count - 1
        }
        return objectRaw
    }
}


/// KSwiftK has two object domains: managed heap objects tracked by `heapObjects`
/// and retained runtime boxes tracked by `objectPointers`. A weak reference never
/// registers its referent as a GC root; `get()` returns null once the referent is
/// no longer present in either domain.
final class RuntimeWeakReferenceBox: @unchecked Sendable {
    private enum ReferentKind {
        case immediate
        case heap(generation: UInt64)
        case runtimeObject
    }

    private let lock = NSLock()
    private var objectRaw: Int?
    private let referentKind: ReferentKind
    private weak var runtimeObject: AnyObject?

    init(objectRaw: Int) {
        self.objectRaw = objectRaw
        // Primitive values may arrive here as immediate words rather than
        // registered object handles. Classify only by runtime registries; do
        // not dereference an ABI word to decide whether it is a pointer.
        let (kind, object): (ReferentKind, AnyObject?) = runtimeStorage.withGCLock { state in
            let key = UInt(bitPattern: objectRaw)
            if let allocation = state.heapObjects[key] {
                return (.heap(generation: allocation.generation), nil)
            }
            guard state.objectPointers.contains(key),
                  let pointer = UnsafeMutableRawPointer(bitPattern: objectRaw)
            else { return (.immediate, nil) }
            let base = runtimePrimitiveBoxBasePointer(from: objectRaw) ?? pointer
            let object = Unmanaged<AnyObject>.fromOpaque(base).retain().takeRetainedValue()
            return (.runtimeObject, object)
        }
        self.referentKind = kind
        self.runtimeObject = object
    }

    func get(rootSlot: Int? = nil) -> Int {
        lock.lock()
        let current = objectRaw
        let runtimeObject = runtimeObject
        lock.unlock()

        guard let current, current != runtimeNullSentinelInt else {
            runtimeStoreWeakResultInShadow(rootSlot, value: runtimeNullSentinelInt)
            return runtimeNullSentinelInt
        }
        let live: Bool
        switch referentKind {
        case .immediate:
            live = true
            runtimeStoreWeakResultInShadow(rootSlot, value: current)
        case .heap, .runtimeObject:
            let threadID = ObjectIdentifier(Thread.current)
            live = withExtendedLifetime(runtimeObject) {
                runtimeStorage.withGCLock { state in
                    let key = UInt(bitPattern: current)
                    let isLive: Bool
                    switch referentKind {
                    case let .heap(generation):
                        isLive = state.heapObjects[key]?.generation == generation
                    case .runtimeObject:
                        // Retaining the weak Swift object prevents its address
                        // from being recycled during the registry check.
                        isLive = runtimeObject != nil && state.objectPointers.contains(key)
                    case .immediate:
                        isLive = true
                    }
                    guard isLive else { return false }
                    if let count = state.shadowFrames[threadID]?.count, count > 0 {
                        if let rootSlot, rootSlot >= 0 {
                            state.shadowFrames[threadID]?[count - 1].slots[rootSlot] = current
                        } else {
                            // Unframed native calls need their own root contract.
                            // A legacy call in a frame is conservative until pop.
                            runtimeRecordShadowHandoffLocked(current, threadID: threadID, state: &state)
                        }
                    }
                    return true
                }
            }
        }
        guard live else {
            clear()
            runtimeStoreWeakResultInShadow(rootSlot, value: runtimeNullSentinelInt)
            // The Kotlin-level `get(): T?` is a generic Any-erased slot, where a
            // reference's null representation is `runtimeNullSentinelInt` (bare
            // `0` there is otherwise read back as a boxed `Int` zero, not null;
            // see KSP-1255's WeakReference constructor migration for how this
            // surfaced).
            return runtimeNullSentinelInt
        }
        return current
    }

    func clear() {
        lock.lock()
        // `nil` marks a cleared weak reference; zero is a live immediate value
        // (Int(0), Boolean(false), or Char(0)).
        objectRaw = nil
        lock.unlock()
    }
}

private func runtimeStoreWeakResultInShadow(_ slot: Int?, value: Int) {
    guard let slot, slot >= 0 else { return }
    let threadID = ObjectIdentifier(Thread.current)
    runtimeStorage.withGCLock { state in
        if let count = state.shadowFrames[threadID]?.count, count > 0 {
            state.shadowFrames[threadID]?[count - 1].slots[slot] = value
        }
    }
}

private func runtimeWeakReferenceBox(from weakRefRaw: Int) -> RuntimeWeakReferenceBox? {
    resolveRuntimeHandle(weakRefRaw, as: RuntimeWeakReferenceBox.self)
}

@_cdecl("kk_weak_ref_create")
public func kk_weak_ref_create(_ objectRaw: Int) -> Int {
    registerRuntimeObject(RuntimeWeakReferenceBox(objectRaw: objectRaw))
}

@_cdecl("kk_weak_ref_get")
public func kk_weak_ref_get(_ weakRefRaw: Int) -> Int {
    guard let box = runtimeWeakReferenceBox(from: weakRefRaw) else {
        return runtimeNullSentinelInt
    }
    return box.get()
}

/// Generated callers supply their shadow slot so a successful load and its
/// strong root are published atomically with respect to collection.
@_cdecl("kk_weak_ref_get_rooted")
public func kk_weak_ref_get_rooted(_ weakRefRaw: Int, _ slot: Int) -> Int {
    guard let box = runtimeWeakReferenceBox(from: weakRefRaw) else {
        runtimeStoreWeakResultInShadow(slot, value: runtimeNullSentinelInt)
        return runtimeNullSentinelInt
    }
    return box.get(rootSlot: slot)
}

@_cdecl("kk_weak_ref_clear")
public func kk_weak_ref_clear(_ weakRefRaw: Int) -> Int {
    guard let box = runtimeWeakReferenceBox(from: weakRefRaw) else {
        return 0
    }
    box.clear()
    return 0
}


/// The cleaner keeps the value and cleanup function reachable until either
/// `clean()` invokes the function once or `dispose()` drops both handles without
/// invoking it. Automatic finalization is intentionally not modeled here.
final class RuntimeCleanerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var valueRaw: Int
    private var blockRaw: Int
    private var isDisposed = false

    init(valueRaw: Int, blockRaw: Int) {
        self.valueRaw = valueRaw
        self.blockRaw = blockRaw
    }

    func clean(outThrown: UnsafeMutablePointer<Int>?) -> Int {
        lock.lock()
        guard !isDisposed else {
            lock.unlock()
            return 0
        }
        isDisposed = true
        let value = valueRaw
        let block = blockRaw
        valueRaw = 0
        blockRaw = 0
        lock.unlock()

        guard block != 0 else {
            outThrown?.pointee = runtimeAllocateThrowable(message: "Invalid cleaner block")
            return 0
        }
        _ = kk_function_invoke(block, value, outThrown)
        return 0
    }

    func dispose() {
        lock.lock()
        isDisposed = true
        valueRaw = 0
        blockRaw = 0
        lock.unlock()
    }
}

private func runtimeCleanerBox(from cleanerRaw: Int) -> RuntimeCleanerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: cleanerRaw) else {
        return nil
    }
    let key = UInt(bitPattern: ptr)
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(key)
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: RuntimeCleanerBox.self)
}

@_cdecl("kk_cleaner_create")
public func kk_cleaner_create(_ valueRaw: Int, _ blockRaw: Int) -> Int {
    guard blockRaw != 0 else {
        return 0
    }
    return registerRuntimeObject(RuntimeCleanerBox(valueRaw: valueRaw, blockRaw: blockRaw))
}

public func kk_cleaner_clean(_ cleanerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard let box = runtimeCleanerBox(from: cleanerRaw) else {
        return 0
    }
    return box.clean(outThrown: outThrown)
}

public func kk_cleaner_dispose(_ cleanerRaw: Int) -> Int {
    guard let box = runtimeCleanerBox(from: cleanerRaw) else {
        return 0
    }
    box.dispose()
    return 0
}


protocol RuntimeChildReferenceProviding {
    /// Return all `Int` handles that this box treats as direct child object refs.
    /// Only handles that are non-zero and registered in `objectPointers` are
    /// meaningful; `freeze` will skip all others.
    var childRefs: [Int] { get }
}

private let runtimeFrozenSet = RuntimeFrozenRegistry()

private final class RuntimeFrozenRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var frozen: Set<UInt> = []

    /// A per-call visited set prevents infinite loops on cyclic graphs.
    func freezeRecursive(_ root: Int) {
        guard root != 0 else { return }
        var visited: Set<UInt> = []
        var queue: [Int] = [root]
        var index = 0
        while index < queue.count {
            let raw = queue[index]
            index += 1
            guard raw != 0 else { continue }
            let key = UInt(bitPattern: raw)
            guard visited.insert(key).inserted else { continue }
            guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { continue }
            let object = runtimeStorage.withGCLock { state -> AnyObject? in
                let isRegistered = state.objectPointers.contains(key)
                guard raw == root || isRegistered || state.heapObjects[key] != nil else { return nil }
                lock.lock()
                frozen.insert(key)
                lock.unlock()
                guard isRegistered else { return nil }
                // Primitive box handles are tagged; retain the base object while
                // still holding gcLock so explicit release cannot invalidate it.
                let basePtr = runtimePrimitiveBoxBasePointer(from: raw) ?? ptr
                return Unmanaged<AnyObject>.fromOpaque(basePtr).retain().takeRetainedValue()
            }
            if let provider = object as? RuntimeChildReferenceProviding {
                for child in provider.childRefs where child != 0 {
                    let childKey = UInt(bitPattern: child)
                    if !visited.contains(childKey) {
                        queue.append(child)
                    }
                }
            }
        }
    }

    func isFrozen(_ raw: Int) -> Bool {
        guard raw != 0 else { return false }
        lock.lock()
        defer { lock.unlock() }
        return frozen.contains(UInt(bitPattern: raw))
    }

    func remove(_ raw: Int) {
        guard raw != 0 else { return }
        lock.lock()
        frozen.remove(UInt(bitPattern: raw))
        lock.unlock()
    }

}

func runtimeForgetFrozenObject(_ raw: Int) {
    runtimeFrozenSet.remove(raw)
}

@discardableResult
@_cdecl("kk_freeze_object")
public func kk_freeze_object(_ objectRaw: Int) -> Int {
    runtimeFrozenSet.freezeRecursive(objectRaw)
    return objectRaw
}

public func kk_is_frozen(_ objectRaw: Int) -> Int {
    runtimeFrozenSet.isFrozen(objectRaw) ? 1 : 0
}


/// Each Worker owns a dedicated serial `DispatchQueue`.  Jobs submitted via
/// `execute` are run in FIFO order on that queue.
final class RuntimeWorkerBox: @unchecked Sendable {
    /// Guards `terminated`/`pendingJobs` and doubles as the condition
    /// `waitForTermination` parks on until `requestTermination` broadcasts.
    private let lock = NSCondition()
    private let queue: DispatchQueue
    let name: String?
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private var terminated = false
    private var pendingJobs: Int = 0

    init(name: String?) {
        self.name = name
        let queueName = name ?? "anonymous"
        self.queue = DispatchQueue(
            label: "kswiftk.worker.\(queueName)",
            qos: .userInitiated
        )
        self.queue.setSpecific(key: queueSpecificKey, value: ())
    }

    /// The registry handle for this box, i.e. the same `Int` `registerRuntimeObject`
    /// returned for it. Recomputed from `self`'s own address rather than stored,
    /// since it is only needed off the hot allocation path (current-worker tracking).
    private var selfHandle: Int {
        Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
    }

    /// Box wrapping the handle tracked per-thread by `currentWorkerHandle`/
    /// `runAsCurrentWorker`. Boxed because the shared pthread-local helpers
    /// (CORO-003) store `AnyObject`, not raw `Int`.
    private final class CurrentWorkerHandleBox: @unchecked Sendable {
        let handle: Int
        init(handle: Int) { self.handle = handle }
    }

    /// pthread-local key tracking which worker's job is currently executing on
    /// the calling thread. Uses the CORO-003 pthread helpers rather than
    /// `Thread.current.threadDictionary`, matching this runtime's established
    /// thread-local convention (see `RuntimeCoroutine.swift`).
    private static let currentWorkerPthreadKey: pthread_key_t = makePthreadKey()

    /// Runs `body` with `handle` recorded as the current thread's worker, restoring
    /// whatever was recorded before (there is none, ordinarily — worker jobs don't
    /// nest — but restoring rather than clearing unconditionally stays correct if
    /// a job synchronously drives another worker's queue).
    private static func runAsCurrentWorker(_ handle: Int, _ body: () -> Void) {
        let previous: CurrentWorkerHandleBox? = pthreadGetValue(currentWorkerPthreadKey)
        pthreadSetValue(currentWorkerPthreadKey, CurrentWorkerHandleBox(handle: handle))
        defer {
            pthreadSetValue(currentWorkerPthreadKey, previous)
        }
        body()
    }

    /// The handle of the worker whose job is currently executing on the calling
    /// thread, or `nil` if the calling thread isn't currently running a worker job
    /// (e.g. the main thread, or a thread GCD spun up outside `execute`/`executeAfter`).
    static func currentWorkerHandle() -> Int? {
        let box: CurrentWorkerHandleBox? = pthreadGetValue(currentWorkerPthreadKey)
        return box?.handle
    }

    /// Returns false if the worker has been terminated.
    @discardableResult
    func execute(_ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return false
        }
        pendingJobs += 1
        lock.unlock()

        let handle = selfHandle
        queue.async { [weak self] in
            RuntimeWorkerBox.runAsCurrentWorker(handle, work)
            self?.lock.lock()
            self?.pendingJobs -= 1
            self?.lock.unlock()
        }
        return true
    }

    /// Request termination of the worker.  If `processScheduled` is true, drain
    /// remaining jobs before terminating; otherwise abandon pending jobs.
    func requestTermination(processScheduled: Bool) {
        lock.lock()
        terminated = true
        lock.broadcast()
        lock.unlock()

        if processScheduled {
            let group = DispatchGroup()
            group.enter()
            queue.async {
                group.leave()
            }
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            group.wait()
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
        }
    }

    var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    func waitForTermination() {
        lock.lock()
        defer { lock.unlock() }
        while !terminated {
            let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
            lock.wait()
            lock.unlock()
            if gcBlocking { runtimeGCSafepoints.endBlocking() }
            lock.lock()
        }
    }

    /// Returns false if the worker is already terminated.
    @discardableResult
    func executeAfter(deadline: DispatchTime, _ work: @escaping @Sendable () -> Void) -> Bool {
        lock.lock()
        guard !terminated else {
            lock.unlock()
            return false
        }
        pendingJobs += 1
        lock.unlock()

        let handle = selfHandle
        queue.asyncAfter(deadline: deadline) { [weak self] in
            RuntimeWorkerBox.runAsCurrentWorker(handle, work)
            self?.lock.lock()
            self?.pendingJobs -= 1
            self?.lock.unlock()
        }
        return true
    }

    /// Dispatch queues do not expose Kotlin/Native's worker event loop, so a
    /// synchronous queue drain is the closest equivalent.  Avoid synchronizing
    /// on the same queue because processQueue may itself be called by a worker job.
    @discardableResult
    func processQueue() -> Bool {
        lock.lock()
        let hadPendingJobs = pendingJobs > 0
        lock.unlock()

        guard DispatchQueue.getSpecific(key: queueSpecificKey) == nil else {
            return hadPendingJobs
        }
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        queue.sync {}
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        return hadPendingJobs
    }

    /// The current runtime has no separate wake-up primitive, therefore an
    /// indefinite park is represented as an immediate timeout. Timed parks
    /// still preserve the observable delay and process flag behavior.
    @discardableResult
    func park(timeoutMicroseconds: Int, process: Bool) -> Bool {
        if process {
            _ = processQueue()
        }
        guard timeoutMicroseconds > 0 else {
            return false
        }
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        Thread.sleep(forTimeInterval: Double(timeoutMicroseconds) / 1_000_000.0)
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        return false
    }

    func platformThreadID() -> UInt64 {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return runtimeCurrentPlatformThreadID()
        }
        var threadID: UInt64 = 0
        let gcBlocking = runtimeGCSafepoints.beginBlockingIfEnrolled()
        queue.sync {
            threadID = runtimeCurrentPlatformThreadID()
        }
        if gcBlocking { runtimeGCSafepoints.endBlocking() }
        return threadID
    }
}

@_cdecl("kk_worker_new")
public func kk_worker_new(_ nameRaw: Int) -> Int {
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw))
    let handle = registerRuntimeObject(RuntimeWorkerBox(name: name))
    registerActiveWorker(handle: handle)
    return handle
}

/// Lazily-created stand-in for the implicit worker that owns the main thread
/// (and any other thread that never runs inside `RuntimeWorkerBox.execute`).
/// Kotlin/Native eagerly creates this at process start; here it's created on
/// first use since nothing else needs its identity until `Worker.current` (or
/// a `WorkerBoundReference` built off the main thread) is asked for it.
private final class MainWorkerHandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: Int = 0

    func resolve() -> Int {
        lock.lock()
        defer { lock.unlock() }
        if handle == 0 {
            handle = registerRuntimeObject(RuntimeWorkerBox(name: nil))
            registerActiveWorker(handle: handle)
        }
        return handle
    }
}

private let mainWorkerHandleBox = MainWorkerHandleBox()

/// Returns the handle of the worker currently executing on the calling thread,
/// or the shared main-worker handle if the calling thread isn't running a job
/// dispatched through `RuntimeWorkerBox.execute`/`executeAfter`.
func runtimeCurrentWorkerHandle() -> Int {
    RuntimeWorkerBox.currentWorkerHandle() ?? mainWorkerHandleBox.resolve()
}

@_cdecl("kk_worker_execute")
public func kk_worker_execute(
    _ workerHandle: Int,
    _ modeRaw: Int,
    _ producerFnPtr: Int,
    _ producerClosureRaw: Int,
    _ jobFnPtr: Int,
    _ jobClosureRaw: Int
) -> Int {
    _ = modeRaw
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    guard producerFnPtr != 0, jobFnPtr != 0 else {
        return 0
    }

    kk_gc_shadow_push()
    var returnedFuture = 0
    defer { runtimePopNativeGCShadowFrame(returnedFuture, 0) }
    var producerThrown = 0
    let producedRaw = runtimeInvokeClosureThunkMaybeWrapped(
        fnPtr: producerFnPtr,
        closureRaw: producerClosureRaw,
        outThrown: &producerThrown
    )
    guard producerThrown == 0 else {
        return 0
    }

    let futureHandle = kk_future_new()
    guard futureHandle != 0 else {
        return 0
    }
    // `jobFnPtr`/`jobClosureRaw` can arrive as a `kk_function_create_1`-wrapped
    // handle instead of a raw pair: CallLowerer's `kk_worker_execute` call-site
    // expansion (CallLowerer+MemberCallEmission.swift / +ClosureAdapters.swift,
    // `appendClosureArgumentsIfNeeded`) expands `producer` via
    // `makeClosureThunkExpandedArguments`, which always resolves to a genuine
    // raw pair, but expands `job` via `makeCollectionHOFExpandedArguments`,
    // whose no-compile-time-info fallback forwards the argument expression
    // as-is with a literal `0` closureRaw — the same fallback documented on
    // `runtimeInvokeCollectionLambda1MaybeWrapped`. Resolve here, on the
    // calling thread, while the handle is still reachable from this call's
    // own arguments — see `resolveFunctionValuePair`. The queued closure
    // below runs later on the worker's dispatch queue and captures only the
    // resolved raw (fnPtr, closureRaw) pair, so it carries no dependency on
    // the wrapper box surviving until the job actually executes.
    let resolvedJob = resolveFunctionValuePair(fnPtr: jobFnPtr, closureRaw: jobClosureRaw)
    let queuedRoots = RuntimeQueuedGCRoots([resolvedJob.closureRaw, producedRaw, futureHandle])
    let submitted = worker.execute {
        defer { queuedRoots.finish() }
        kk_gc_shadow_push()
        defer { runtimePopNativeGCShadowFrame(0, 0) }
        var jobThrown = 0
        let resultRaw = runtimeInvokeCollectionLambda1(
            fnPtr: resolvedJob.fnPtr,
            closureRaw: resolvedJob.closureRaw,
            value: producedRaw,
            outThrown: &jobThrown
        )
        _ = kk_future_complete(futureHandle, jobThrown == 0 ? resultRaw : 0)
    }
    if !submitted {
        queuedRoots.finish()
        _ = runtimeReleaseObject(futureHandle)
    }
    returnedFuture = submitted ? futureHandle : 0
    return returnedFuture
}

@_cdecl("kk_worker_request_termination")
public func kk_worker_request_termination(_ workerHandle: Int, _ processScheduledRaw: Int) -> Int {
    guard workerHandle != 0,
          let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle),
          let worker = tryCast(ptr, to: RuntimeWorkerBox.self)
    else {
        return 0
    }
    worker.requestTermination(processScheduled: processScheduledRaw != 0)
    unregisterActiveWorker(handle: workerHandle)
    let futureHandle = kk_future_new()
    guard futureHandle != 0 else {
        return 0
    }
    _ = kk_future_complete(futureHandle, 1)
    return futureHandle
}

@_cdecl("kk_worker_is_terminated")
public func kk_worker_is_terminated(_ workerHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        return 1
    }
    guard let worker = tryCast(ptr, to: RuntimeWorkerBox.self) else {
        return 1
    }
    return worker.isTerminated ? 1 : 0
}

@_cdecl("kk_worker_name")
public func kk_worker_name(_ workerHandle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: workerHandle) else {
        return 0
    }
    guard let worker = tryCast(ptr, to: RuntimeWorkerBox.self) else {
        return 0
    }
    guard let name = worker.name else {
        return 0
    }
    return registerRuntimeObject(RuntimeStringBox(name))
}


private final class RuntimeCNameRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Int] = [:]

    func register(externName: String, fnPtr: Int) {
        lock.lock()
        defer { lock.unlock() }
        entries[externName] = fnPtr
    }

    func lookup(externName: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[externName] ?? 0
    }

}

private let runtimeCNameRegistry = RuntimeCNameRegistry()

public func kk_cname_register(_ externNameRaw: Int, _ fnPtr: Int) -> Int {
    guard let namePtr = UnsafeMutableRawPointer(bitPattern: externNameRaw),
          let name = extractString(from: namePtr)
    else {
        return 0
    }
    runtimeCNameRegistry.register(externName: name, fnPtr: fnPtr)
    return 0
}

public func kk_cname_lookup(_ externNameRaw: Int) -> Int {
    guard let namePtr = UnsafeMutableRawPointer(bitPattern: externNameRaw),
          let name = extractString(from: namePtr)
    else {
        return 0
    }
    return runtimeCNameRegistry.lookup(externName: name)
}

