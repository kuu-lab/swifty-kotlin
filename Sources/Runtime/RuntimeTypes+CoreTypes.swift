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
typealias KKFunctionEntryPoint7 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint7 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint8 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint8 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint9 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint9 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint10 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint10 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint11 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint11 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint12 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint12 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint13 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint13 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint14 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint14 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint15 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint15 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint16 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint16 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint17 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint17 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint18 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint18 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint19 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint19 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint20 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint20 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint21 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint21 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKFunctionEntryPoint22 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias KKClosureFunctionEntryPoint22 = @convention(c) (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int

final class RuntimeStringBox {
    let value: String
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

    /// The box is the storage's canonical boxed handle, so a flat→raw bridge
    /// of the same buffer resolves back to this box.
    func flatStringStorage() -> RuntimeFlatStringStorage {
        utf16CodeUnitsLock.lock()
        defer { utf16CodeUnitsLock.unlock() }
        if let cachedFlatStorage {
            return cachedFlatStorage
        }
        let storage = RuntimeFlatStringStorage(value)
        runtimeRegisterFlatStringStorage(storage, canonicalBox: canonicalFlatStringBox())
        cachedFlatStorage = storage
        return storage
    }

    /// A `kk_tag_value_class_box` tag lives in the side-table nominal-type
    /// registry, not in the box itself. Using `self` as the storage's
    /// canonical box would make every later `kk_string_from_flat` of this
    /// payload return the value-class box again — `x.toString` inside
    /// `S(x=…)` would then re-dispatch `S.toString` and recurse (KUU-3251).
    /// Tagged clones carry `untaggedCanonicalAlias` back to the payload box
    /// they were cloned from so the bridge preserves object identity; any
    /// other nominally-typed box resolves to a fresh untagged peer instead.
    var untaggedCanonicalAlias: RuntimeStringBox?

    private func canonicalFlatStringBox() -> RuntimeStringBox {
        if let untaggedCanonicalAlias {
            return untaggedCanonicalAlias
        }
        let raw = Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        // The nominal type can sit on either this exact handle (in-place tag)
        // or its primitive-tag-bits handle (registerTaggedPrimitiveBox clone).
        let taggedPrimitiveRaw = Int(bitPattern: UInt(bitPattern: raw) | runtimePrimitiveBoxTag)
        guard runtimeObjectTypeID(rawValue: raw) != nil
                || runtimeObjectTypeID(rawValue: taggedPrimitiveRaw) != nil
        else {
            return self
        }
        let untagged = RuntimeStringBox(value)
        _ = registerRuntimeObject(untagged)
        return untagged
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
