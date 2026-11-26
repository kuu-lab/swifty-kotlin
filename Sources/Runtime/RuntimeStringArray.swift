import Foundation
import RuntimeABI

@_cdecl("kk_abort_unreachable")
public func kk_abort_unreachable(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    _ = outThrown
    runtimeStructuredPanic("reached unreachable code")
}

let runtimePanicDiagnosticCode = "KSWIFTK-RUNTIME-0001"

func runtimeStructuredPanicMessage(_ message: String) -> String {
    "KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(message)"
}

@inline(__always)
func runtimeStructuredPanic(_ message: @autoclosure () -> String) -> Never {
    fatalError(runtimeStructuredPanicMessage(message()))
}

enum RuntimeTypeTokenEncoding {
    static let baseMask: Int64 = 0xFF
    static let nullableBit: Int64 = 0x100
    static let payloadShift: Int64 = 9
    static let payloadMask: Int64 = (1 << 55) - 1
    static let anyBase: Int64 = 1
    static let stringBase: Int64 = 2
    static let intBase: Int64 = 3
    static let booleanBase: Int64 = 4
    static let nullBase: Int64 = 5
    static let nominalBase: Int64 = 6
    static let uintBase: Int64 = 7
    static let ulongBase: Int64 = 8
    static let ubyteBase: Int64 = 9
    static let ushortBase: Int64 = 10
    static let byteBase: Int64 = 16
    static let shortBase: Int64 = 17
    static let longBase: Int64 = 11
    static let doubleBase: Int64 = 12
    static let floatBase: Int64 = 13
    static let charBase: Int64 = 14
    static let unitBase: Int64 = 15
    // Payload packs the FunctionN arity in bits 0-7 and the suspend flag in
    // bit 8.
    static let functionBase: Int64 = 18

    static func functionPayloadParts(_ payload: Int64) -> (arity: Int, isSuspend: Bool) {
        (Int(payload & 0xFF), (payload & 0x100) != 0)
    }
}

func runtimePanicMessage(fromCString cstr: UnsafePointer<CChar>) -> String {
    runtimeStructuredPanicMessage(String(cString: cstr))
}

final class RuntimeFlatStringStorage: @unchecked Sendable {
    let data: UnsafeMutablePointer<UInt8>
    let length: Int
    let byteCount: Int
    let hash: Int
    weak var canonicalBox: RuntimeStringBox?
    private var cachedUTF16CodeUnits: [UInt16]?
    private let utf16CodeUnitsLock = NSLock()

    init(_ value: String) {
        let bytes = Array(value.utf8)
        self.length = runtimeKotlinStringUTF16Length(value)
        self.byteCount = bytes.count
        self.hash = 0
        self.data = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
        if bytes.isEmpty {
            data.initialize(to: 0)
        } else {
            data.initialize(from: bytes, count: bytes.count)
        }
    }

    var utf16CodeUnits: [UInt16] {
        utf16CodeUnitsLock.lock()
        defer { utf16CodeUnitsLock.unlock() }
        if let cachedUTF16CodeUnits {
            return cachedUTF16CodeUnits
        }
        let buffer = UnsafeBufferPointer(start: data, count: byteCount)
        let units = runtimeKotlinStringUTF16CodeUnits(String(decoding: buffer, as: UTF8.self))
        cachedUTF16CodeUnits = units
        return units
    }

    deinit {
        data.deallocate()
    }
}

private struct RuntimeWeakStringBox {
    weak let box: RuntimeStringBox?
}

private final class RuntimeFlatStringStorageRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var storageByDataPointer: [UInt: RuntimeFlatStringStorage] = [:]
    private var foreignBoxByDataPointer: [UInt: RuntimeWeakStringBox] = [:]

    func register(_ storage: RuntimeFlatStringStorage, canonicalBox: RuntimeStringBox?) {
        lock.lock()
        if let canonicalBox, storage.canonicalBox == nil {
            storage.canonicalBox = canonicalBox
        }
        storageByDataPointer[UInt(bitPattern: storage.data)] = storage
        lock.unlock()
    }

    func storage(for data: UnsafePointer<UInt8>?) -> RuntimeFlatStringStorage? {
        guard let data else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer[UInt(bitPattern: data)]
    }

    @discardableResult
    func unregister(data: UnsafePointer<UInt8>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer.removeValue(forKey: UInt(bitPattern: data)) != nil
    }

    func canonicalBoxRaw(
        for data: UnsafePointer<UInt8>,
        length: Int,
        byteCount: Int,
        hash: Int
    ) -> Int {
        let key = UInt(bitPattern: data)
        lock.lock()
        if let box = storageByDataPointer[key]?.canonicalBox {
            lock.unlock()
            return Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
        }
        lock.unlock()

        let string = runtimeStringFromFlatFields(
            data: data,
            length: length,
            byteCount: byteCount,
            hash: hash
        )

        lock.lock()
        defer { lock.unlock() }
        if let box = storageByDataPointer[key]?.canonicalBox {
            return Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
        }
        // A foreign buffer (literal or transient caller buffer) may reuse its
        // address for different contents, so a dedup hit is only valid when
        // the decoded bytes still match the cached box.
        if let box = foreignBoxByDataPointer[key]?.box, box.value == string {
            return Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
        }
        let box = RuntimeStringBox(string)
        let raw = registerRuntimeObject(box)
        if let storage = storageByDataPointer[key] {
            storage.canonicalBox = box
        } else {
            foreignBoxByDataPointer[key] = RuntimeWeakStringBox(box: box)
        }
        return raw
    }

    var liveStorageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer.count
    }
}

private let runtimeFlatStringStorageRegistry = RuntimeFlatStringStorageRegistry()

func runtimeFlatStringRegisteredUTF16CodeUnits(
    data: UnsafePointer<UInt8>?
) -> [UInt16]? {
    runtimeFlatStringStorageRegistry.storage(for: data)?.utf16CodeUnits
}

func runtimeFlatStringLiveStorageCountForTesting() -> Int {
    runtimeFlatStringStorageRegistry.liveStorageCount
}

func runtimeStringFromFlatFields(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> String {
    _ = (length, hash)
    guard let data, byteCount >= 0 else {
        return ""
    }
    let buffer = UnsafeBufferPointer(start: data, count: byteCount)
    return String(decoding: buffer, as: UTF8.self)
}

func runtimeRegisterFlatStringStorage(
    _ storage: RuntimeFlatStringStorage,
    canonicalBox: RuntimeStringBox? = nil
) {
    runtimeFlatStringStorageRegistry.register(storage, canonicalBox: canonicalBox)
}

func runtimeRegisterFlatString(
    _ value: String,
    outLength: UnsafeMutablePointer<Int>?,
    outByteCount: UnsafeMutablePointer<Int>?,
    outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let storage = RuntimeFlatStringStorage(value)
    runtimeRegisterFlatStringStorage(storage)
    outLength?.pointee = storage.length
    outByteCount?.pointee = storage.byteCount
    outHash?.pointee = storage.hash
    return storage.data
}

@_cdecl("kk_string_from_flat")
public func kk_string_from_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard let data else {
        // Null `String?` flattens to a nil data pointer; the boxed raw must
        // carry the canonical null sentinel so `== null`/Elvis/`?.` checks
        // and erased slot boxing recognize it (KUU-3614). A bare 0 would be
        // read as a non-null value by `runtimeValuesEqual`/`kk_structural_eq`.
        return runtimeNullSentinelInt
    }
    return runtimeFlatStringStorageRegistry.canonicalBoxRaw(
        for: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
}

@_cdecl("kk_string_to_flat")
public func kk_string_to_flat(
    _ raw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    guard raw != runtimeNullSentinelInt,
          raw != 0,
          let box = extractStringBox(from: UnsafeMutableRawPointer(bitPattern: raw))
    else {
        outLength?.pointee = 0
        outByteCount?.pointee = 0
        outHash?.pointee = 0
        return nil
    }
    let storage = box.flatStringStorage()
    outLength?.pointee = storage.length
    outByteCount?.pointee = storage.byteCount
    outHash?.pointee = storage.hash
    return storage.data
}

/// Releases the retained buffer behind a runtime-produced flat `String`
/// aggregate: the registry drops the storage and its backing allocation is
/// freed. The `data` pointer — and every aggregate still carrying it — must
/// not be used after a successful call.
///
/// Returns `1` when a registered storage was dropped, and `0` when `data` is
/// nil, a string literal or other foreign buffer, or an already-released
/// buffer, making the call idempotent for stale pointers.
public func kk_flat_string_release(_ data: UnsafePointer<UInt8>?) -> Int {
    guard let data else {
        return 0
    }
    return runtimeFlatStringStorageRegistry.unregister(data: data) ? 1 : 0
}

@_cdecl("kk_string_from_utf8")
public func kk_string_from_utf8(_ ptr: UnsafePointer<UInt8>, _ len: Int32) -> UnsafeMutableRawPointer {
    let count = max(0, Int(len))
    let buffer = UnsafeBufferPointer(start: ptr, count: count)
    let string = KotlinStringSurrogateEncoding.encode(String(decoding: buffer, as: UTF8.self))
    let box = RuntimeStringBox(string)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    runtimeRegisterCharSequenceItable(Int(bitPattern: opaque))
    return opaque
}

@_cdecl("__kk_string_concat_flat")
public func __kk_string_concat_flat(
    _ lhsData: UnsafePointer<UInt8>?,
    _ lhsLength: Int,
    _ lhsByteCount: Int,
    _ lhsHash: Int,
    _ rhsData: UnsafePointer<UInt8>?,
    _ rhsLength: Int,
    _ rhsByteCount: Int,
    _ rhsHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    // BUG-B: a nil data pointer is the flat ABI's unambiguous signal for an
    // actually-null String -- a genuinely empty string ("") always has a
    // non-nil (zero-length) buffer, both for literals (LLVM never returns a
    // null pointer for a global string constant) and at runtime
    // (`RuntimeFlatStringStorage.init` always allocates at least 1 byte).
    // String templates and the `+`/`String?.plus` operators must render a
    // null operand as the text "null", matching every other Kotlin
    // reference type -- silently treating it as "" (as
    // `runtimeStringFromFlatFields` does for every *other* caller that
    // really does mean "absent data") hid an uninitialized-field bug behind
    // output that merely looked wrong instead of null.
    let lhs = lhsData == nil ? "null" : runtimeStringFromFlatFields(
        data: lhsData,
        length: lhsLength,
        byteCount: lhsByteCount,
        hash: lhsHash
    )
    let rhs = rhsData == nil ? "null" : runtimeStringFromFlatFields(
        data: rhsData,
        length: rhsLength,
        byteCount: rhsByteCount,
        hash: rhsHash
    )
    return runtimeRegisterFlatString(
        lhs + rhs,
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_compareTo_flat")
public func kk_string_compareTo_flat(
    _ lhsData: UnsafePointer<UInt8>?,
    _ lhsLength: Int,
    _ lhsByteCount: Int,
    _ lhsHash: Int,
    _ rhsData: UnsafePointer<UInt8>?,
    _ rhsLength: Int,
    _ rhsByteCount: Int,
    _ rhsHash: Int
) -> Int {
    let lhs = runtimeStringFromFlatFields(
        data: lhsData,
        length: lhsLength,
        byteCount: lhsByteCount,
        hash: lhsHash
    )
    let rhs = runtimeStringFromFlatFields(
        data: rhsData,
        length: rhsLength,
        byteCount: rhsByteCount,
        hash: rhsHash
    )
    return runtimeCompareStrings(lhs, rhs)
}

@_cdecl("__kk_string_plus")
public func __kk_string_plus(_ receiverRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeElementToString(receiverRaw)
    let rhs = runtimeElementToString(otherRaw)
    return runtimeMakeStringRaw(lhs + rhs)
}
