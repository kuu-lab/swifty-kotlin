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
    // REFL-002: Additional primitive bases for Long, Double, Float, Char.
    static let longBase: Int64 = 11
    static let doubleBase: Int64 = 12
    static let floatBase: Int64 = 13
    static let charBase: Int64 = 14
    // STDLIB-REFLECT-ABI-001: Unit::class token base.
    static let unitBase: Int64 = 15
    // KUU-1084: Function-type token base. Payload packs the FunctionN arity
    // in bits 0-7 and the suspend flag in bit 8.
    static let functionBase: Int64 = 18

    /// Decodes a function-type token payload into its parts.
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
    /// Canonical boxed handle for this buffer, materialized on the first
    /// flat→raw bridge so repeated conversions share one registered box.
    /// Only mutated under the flat-string registry lock.
    weak var canonicalBox: RuntimeStringBox?
    /// Kotlin UTF-16 code units decoded on first positional access; the flat
    /// bytes never change, so the cache stays valid for the storage's lifetime.
    private var cachedUTF16CodeUnits: [UInt16]?
    private let utf16CodeUnitsLock = NSLock()

    init(_ value: String) {
        let bytes = Array(value.utf8)
        // `length` is the UTF-16 code-unit count used by Kotlin String/CharSequence;
        // `byteCount` is the UTF-8 byte count used by the flat ABI.
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
    weak var box: RuntimeStringBox?
}

private final class RuntimeFlatStringStorageRegistry: @unchecked Sendable {
    private let lock = NSLock()
    /// Owning registry of runtime-produced flat String buffers. Entries
    /// retain their storage until `unregister` (the `kk_flat_string_release`
    /// path) drops them and the buffer is freed.
    private var storageByDataPointer: [UInt: RuntimeFlatStringStorage] = [:]
    /// Canonical boxes deduplicating `kk_string_from_flat` on buffers the
    /// registry does not own (string literals and other foreign pointers).
    private var foreignBoxByDataPointer: [UInt: RuntimeWeakStringBox] = [:]

    func register(_ storage: RuntimeFlatStringStorage, canonicalBox: RuntimeStringBox?) {
        lock.lock()
        if let canonicalBox, storage.canonicalBox == nil {
            storage.canonicalBox = canonicalBox
        }
        storageByDataPointer[UInt(bitPattern: storage.data)] = storage
        lock.unlock()
    }

    /// Storage whose `data` pointer is `data`, when the flat string was
    /// produced by this runtime and has not been released. The pointer key
    /// stays unique among registered entries: released storages free their
    /// buffer and are dropped from the map.
    func storage(for data: UnsafePointer<UInt8>?) -> RuntimeFlatStringStorage? {
        guard let data else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer[UInt(bitPattern: data)]
    }

    /// Drops the storage registered for `data` so its buffer is freed.
    /// Returns false for foreign or already-released pointers.
    @discardableResult
    func unregister(data: UnsafePointer<UInt8>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer.removeValue(forKey: UInt(bitPattern: data)) != nil
    }

    /// Boxed handle that canonically represents `data`. Materializes and
    /// registers a `RuntimeStringBox` on first use so repeated flat→raw
    /// bridges of the same buffer share a single box instead of accumulating
    /// one registered box per call.
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

    /// Number of storages retained by the registry; test support only.
    var liveStorageCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storageByDataPointer.count
    }
}

private let runtimeFlatStringStorageRegistry = RuntimeFlatStringStorageRegistry()

/// Lazily cached UTF-16 code units of a runtime-produced flat string, keyed by
/// its flat `data` pointer. Returns nil when the pointer did not come from
/// `runtimeRegisterFlatString` (string literals and other foreign buffers).
func runtimeFlatStringRegisteredUTF16CodeUnits(
    data: UnsafePointer<UInt8>?
) -> [UInt16]? {
    runtimeFlatStringStorageRegistry.storage(for: data)?.utf16CodeUnits
}

/// Live storages tracked by the flat-string index; test support only.
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

/// Publishes `storage` in the flat-string registry, which retains it until
/// `kk_flat_string_release` unregisters and frees the buffer. `canonicalBox`
/// (when already known, e.g. a `RuntimeStringBox` flattening itself) becomes
/// the handle `kk_string_from_flat` resolves for this buffer.
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
        return 0
    }
    // Identity is preserved when `kk_string_to_flat` registered the source
    // box as the buffer's canonicalBox (generic AtomicReference<T> ABI).
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
    // Native string construction is also used for temporary CharSequence
    // windows created by bundled text helpers. Keep those boxes on the same
    // interface-property itable path as registerRuntimeObject.
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

// STDLIB-TEXT-FN-043: String?.plus(other: Any?): String
// Receiver is passed as Int (intptr) so null receivers produce "null".
// Primitives passed as `other` are already boxed by the ABI lowering pass
// when widened to Any?, so runtimeElementToString handles them correctly.
@_cdecl("__kk_string_plus")
public func __kk_string_plus(_ receiverRaw: Int, _ otherRaw: Int) -> Int {
    let lhs = runtimeElementToString(receiverRaw)
    let rhs = runtimeElementToString(otherRaw)
    return runtimeMakeStringRaw(lhs + rhs)
}

// MARK: - String nullable receiver helpers

@_cdecl("kk_string_isNullOrEmpty_flat")
public func kk_string_isNullOrEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard data != nil else {
        return 1
    }
    let str = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return str.isEmpty ? 1 : 0
}

@_cdecl("kk_string_isNullOrBlank_flat")
public func kk_string_isNullOrBlank_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    guard data != nil else {
        return 1
    }
    let str = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return str.allSatisfy(\.isWhitespace) ? 1 : 0
}

// MARK: - STDLIB-534: String?.orEmpty()

@_cdecl("kk_string_orEmpty_flat")
public func kk_string_orEmpty_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let value = runtimeStringFromFlatFields(
        data: data,
        length: length,
        byteCount: byteCount,
        hash: hash
    )
    return runtimeRegisterFlatString(
        value,
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}
