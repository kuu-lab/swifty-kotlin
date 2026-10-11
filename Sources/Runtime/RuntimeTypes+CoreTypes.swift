import Foundation

public struct KTypeInfo {
    public let fqName: UnsafePointer<CChar>
    public let instanceSize: UInt32
    public let fieldCount: UInt32
    public let fieldOffsets: UnsafePointer<UInt32>
    public let vtableSize: UInt32
    public let vtable: UnsafePointer<UnsafeRawPointer>
    public let itable: UnsafeRawPointer?
    public let gcDescriptor: UnsafeRawPointer?

    public init(
        fqName: UnsafePointer<CChar>,
        instanceSize: UInt32,
        fieldCount: UInt32,
        fieldOffsets: UnsafePointer<UInt32>,
        vtableSize: UInt32,
        vtable: UnsafePointer<UnsafeRawPointer>,
        itable: UnsafeRawPointer?,
        gcDescriptor: UnsafeRawPointer?
    ) {
        self.fqName = fqName
        self.instanceSize = instanceSize
        self.fieldCount = fieldCount
        self.fieldOffsets = fieldOffsets
        self.vtableSize = vtableSize
        self.vtable = vtable
        self.itable = itable
        self.gcDescriptor = gcDescriptor
    }
}

struct KKObjHeader {
    var typeInfo: UnsafePointer<KTypeInfo>?
    var flags: UInt32
    var size: UInt32
}

public protocol KKContinuation {
    var context: UnsafeMutableRawPointer? { get }
    func resumeWith(_ result: UnsafeMutableRawPointer?)
}

typealias KKSuspendEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKThunkEntryPoint = @convention(c) (UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureThunkEntryPoint = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint1 = @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint2 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint3 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint4 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint5 = @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint6 = @convention(c) (Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint1 = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint2 = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint3 = @convention(c) (Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint4 = @convention(c) (Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint5 = @convention(c) (Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint6 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKDelegateObserverEntryPoint = @convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

final class RuntimeStringBox {
    let value: String
    /// Kotlin UTF-16 code units materialized on first positional access.
    /// `value` is immutable, so the cache never invalidates.
    private var cachedUTF16CodeUnits: [UInt16]?
    /// Flat-ABI buffer backing this string, materialized once so repeated
    /// `kk_string_to_flat` bridges share a single registered storage instead
    /// of accumulating one buffer per call. Owned by the flat-string registry,
    /// so the cache stays weak and self-heals after `kk_flat_string_release`.
    private weak var cachedFlatStorage: RuntimeFlatStringStorage?
    private let utf16CodeUnitsLock = NSLock()

    init(_ value: String) {
        self.value = value
    }

    var utf16CodeUnits: [UInt16] {
        utf16CodeUnitsLock.lock()
        defer { utf16CodeUnitsLock.unlock() }
        if let cachedUTF16CodeUnits {
            return cachedUTF16CodeUnits
        }
        let units = runtimeKotlinStringUTF16CodeUnits(value)
        cachedUTF16CodeUnits = units
        return units
    }

    /// UTF-16 length without allocating the code-unit array when nothing has
    /// indexed this string yet.
    var utf16Length: Int {
        utf16CodeUnitsLock.lock()
        let cached = cachedUTF16CodeUnits
        utf16CodeUnitsLock.unlock()
        return cached?.count ?? runtimeKotlinStringUTF16Length(value)
    }

    /// Flat-ABI buffer for `value`, creating and registering one on first use.
    /// The box is the storage's canonical boxed handle, so a flat→raw bridge
    /// of the same buffer resolves back to this box.
    func flatStringStorage() -> RuntimeFlatStringStorage {
        utf16CodeUnitsLock.lock()
        defer { utf16CodeUnitsLock.unlock() }
        if let cachedFlatStorage {
            return cachedFlatStorage
        }
        let storage = RuntimeFlatStringStorage(value)
        runtimeRegisterFlatStringStorage(storage, canonicalBox: self)
        cachedFlatStorage = storage
        return storage
    }
}

struct RuntimeValue {
    static let rawTag = 0
    static let stringTag = 1
    static let charTag = 2

    var tag: Int
    var payload0: Int
    var payload1: Int
    var payload2: Int
    var payload3: Int
    // Static type information used by Any fallback operations. This is kept
    // separate from `tag`, which describes the storage representation.
    var anyFallbackTag: Int32

    init(raw: Int, anyFallbackTag: Int32 = 0) {
        self.tag = Self.rawTag
        self.payload0 = raw
        self.payload1 = 0
        self.payload2 = 0
        self.payload3 = 0
        self.anyFallbackTag = anyFallbackTag
    }

    init(stringData data: Int, length: Int, byteCount: Int, hash: Int) {
        self.tag = Self.stringTag
        self.payload0 = data
        self.payload1 = length
        self.payload2 = byteCount
        self.payload3 = hash
        self.anyFallbackTag = 0
    }

    init(charScalar value: Int) {
        self.tag = Self.charTag
        self.payload0 = value
        self.payload1 = 0
        self.payload2 = 0
        self.payload3 = 0
        self.anyFallbackTag = 0
    }

    var legacyRawValue: Int {
        guard tag == Self.stringTag else {
            return payload0
        }
        guard let data = UnsafePointer<UInt8>(bitPattern: payload0) else {
            return 0
        }
        let string = runtimeStringFromFlatFields(
            data: data,
            length: payload1,
            byteCount: payload2,
            hash: payload3
        )
        return registerRuntimeObject(RuntimeStringBox(string))
    }

    var childReferenceRawValue: Int? {
        guard tag == Self.rawTag, payload0 != 0 else {
            return nil
        }
        return payload0
    }
}

@inline(__always)
func runtimeValuePreservingAnyFallbackTag(
    _ value: RuntimeValue,
    existing: RuntimeValue
) -> RuntimeValue {
    guard value.anyFallbackTag == 0 else { return value }
    var value = value
    value.anyFallbackTag = existing.anyFallbackTag
    return value
}
