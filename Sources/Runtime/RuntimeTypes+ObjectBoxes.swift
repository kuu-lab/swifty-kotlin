import Foundation

class RuntimeArrayBox {
    private final class Storage {
        var values: [RuntimeValue]
        // Canonical handles preserve identity when views are repeated or reversed.
        var viewHandles: [Int64: Int] = [:]
        let viewLock = NSLock()

        init(length: Int) {
            values = Array(repeating: RuntimeValue(raw: 0), count: max(0, length))
        }
    }

    private let storage: Storage

    var values: [RuntimeValue] {
        get {
            storage.values
        }
        set {
            storage.values = newValue
        }
    }

    var elements: [Int] {
        get {
            storage.values.map(\.legacyRawValue)
        }
        set {
            storage.values = newValue.map { RuntimeValue(raw: $0) }
        }
    }

    /// O(1) single-element access. Prefer this over `elements[i]` inside loops:
    /// `elements` materializes the whole array on every get/set, making per-index
    /// loop access O(n) per iteration.
    subscript(index: Int) -> Int {
        get { storage.values[index].legacyRawValue }
        set {
            storage.values[index] = RuntimeValue(
                raw: newValue,
                anyFallbackTag: storage.values[index].anyFallbackTag
            )
        }
    }

    /// Stores a raw field value together with the static tag needed by
    /// Any-erased operations such as `hashCode()`.
    func setValue(_ value: Int, at index: Int, anyFallbackTag: Int32) {
        storage.values[index] = RuntimeValue(raw: value, anyFallbackTag: anyFallbackTag)
    }

    func setValue(_ value: RuntimeValue, at index: Int) {
        storage.values[index] = runtimeValuePreservingAnyFallbackTag(value, existing: storage.values[index])
    }

    var count: Int {
        storage.values.count
    }

    init(length: Int) {
        storage = Storage(length: length)
    }

    private init(sharingStorageOf array: RuntimeArrayBox) {
        storage = array.storage
    }

    /// A distinct, correctly tagged box over the same mutable element storage.
    func primitiveView(rawValue: Int, sourceTypeID: Int64, targetTypeID: Int64) -> Int {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        storage.viewHandles[sourceTypeID] = rawValue
        if let existing = storage.viewHandles[targetTypeID] {
            return existing
        }
        let view = registerRuntimeObject(RuntimeArrayBox(sharingStorageOf: self))
        runtimeRegisterArrayType(rawValue: view, typeID: targetTypeID)
        storage.viewHandles[targetTypeID] = view
        return view
    }
}

final class RuntimeObjectBox: RuntimeArrayBox {
    let classID: Int64
    var coroutineJobHandle: Int = 0
    var backingListBox: RuntimeListBox?
    var backingSetBox: RuntimeSetBox?
    var backingMapBox: RuntimeMapBox?
    var throwableMessage: String?
    var throwableCause: Int
    var throwableStackTraceAddresses: [Int]?
    var throwableSuppressed: [Int]

    init(length: Int, classID: Int64) {
        self.classID = classID
        self.backingListBox = nil
        self.backingSetBox = nil
        self.backingMapBox = nil
        self.throwableMessage = nil
        self.throwableCause = 0
        self.throwableStackTraceAddresses = nil
        self.throwableSuppressed = []
        super.init(length: length)
    }
}

final class RuntimePairBox {
    var firstValue: RuntimeValue
    var secondValue: RuntimeValue
    // MutableMap.MutableEntry pairs retain the destination map so entry.value
    // and setValue() observe subsequent mutations through the live view.
    var mutableMapRaw: Int = 0
    var mutableMapKey: Int = 0

    var first: Int { runtimeCollectionABIValue(firstValue) }
    var second: Int { runtimeCollectionABIValue(secondValue) }

    init(first: Int, second: Int) {
        self.firstValue = RuntimeValue(raw: first)
        self.secondValue = RuntimeValue(raw: second)
    }

    init(firstValue: RuntimeValue, secondValue: RuntimeValue) {
        self.firstValue = firstValue
        self.secondValue = secondValue
    }
}

final class RuntimeTripleBox {
    let firstValue: RuntimeValue
    let secondValue: RuntimeValue
    let thirdValue: RuntimeValue

    var first: Int { firstValue.legacyRawValue }
    var second: Int { secondValue.legacyRawValue }
    var third: Int { thirdValue.legacyRawValue }

    init(first: Int, second: Int, third: Int) {
        self.firstValue = RuntimeValue(raw: first)
        self.secondValue = RuntimeValue(raw: second)
        self.thirdValue = RuntimeValue(raw: third)
    }
}

final class RuntimeIntBox {
    let value: Int
    /// Kotlin type identity, independent of the shared payload/hash representation.
    let primitiveTypeBase: Int64

    /// Static Any-fallback tag captured at the boxing boundary. UInt, UByte,
    /// and UShort share this physical box with Int, but their hashCode() must
    /// reinterpret the zero-extended payload as the signed backing type.
    let anyFallbackTag: Int32

    /// Set when this box represents a Kotlin enum ordinal (an element of
    /// `values()`/`entries`) round-tripped through an Any-erased array slot.
    /// Generic Any-printing paths (__kk_print_raw, runtimeRenderAnyForPrint,
    /// runtimeElementToString) check this to show the entry name instead of
    /// the raw ordinal once the static enum type has been erased. See
    /// kk_enum_box_ordinal.
    let enumEntryName: String?
    /// Stable nominal ID for the enum class represented by this box. Unlike a
    /// plain boxed Int, enum equality must keep two entries from different
    /// enum classes unequal even when their ordinals match.
    let enumClassID: Int64?

    init(
        _ value: Int,
        anyFallbackTag: Int32 = 1,
        primitiveTypeBase: Int64? = nil,
        enumEntryName: String? = nil,
        enumClassID: Int64? = nil
    ) {
        self.value = value
        self.anyFallbackTag = anyFallbackTag
        let defaultPrimitiveTypeBase: Int64 = switch anyFallbackTag {
        case 9: RuntimeTypeTokenEncoding.uintBase
        case 10: RuntimeTypeTokenEncoding.ubyteBase
        case 11: RuntimeTypeTokenEncoding.ushortBase
        default: RuntimeTypeTokenEncoding.intBase
        }
        self.primitiveTypeBase = primitiveTypeBase ?? defaultPrimitiveTypeBase
        self.enumEntryName = enumEntryName
        self.enumClassID = enumClassID
    }
}

final class RuntimeBoolBox {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }
}

/// Boxed Kotlin Unit for Any-erased storage. Direct Unit values remain the
/// compiler's raw zero representation; this box is used only at reference
/// boundaries where Any must retain the value's runtime identity.
final class RuntimeUnitBox {}

final class RuntimeLongBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

/// Boxed `ULong`. Distinct from `RuntimeLongBox` so that boxed-`Any` dispatch
/// (toString/equals/hashCode/compareTo/`is`) can tell a ULong apart from a
/// Long with the same 64-bit pattern — see docs on `kk_box_ulong`.
final class RuntimeULongBox {
    /// Raw 64-bit pattern; interpret via `UInt(bitPattern:)` for the true unsigned value.
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeFloatBox {
    let value: Float

    init(_ value: Float) {
        self.value = value
    }
}

final class RuntimeDoubleBox {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }
}

final class RuntimeCharBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

enum RuntimeCallableRefKind {
    case function
    case property
}

struct RuntimeCallableRefMetadata {
    let nameRaw: Int
    let returnTypeRaw: Int
    let arity: Int
    let kind: RuntimeCallableRefKind
    let isSuspend: Bool
    /// Packed KFunction modifier flags (bit1=inline, bit2=operator,
    /// bit3=infix, bit4=external; bit0 suspend lives in `isSuspend`).
    var modifierFlags: Int = 0
    var invoker: Int = 0
    var environment: Int = 0
    var parameters: Int = 0
    var typeParameters: Int = 0
    var flags: Int = 1
    var visibility: Int = 0
    var setterInvoker: Int = 0
    var setterParameters: Int = 0
    var property: Int = 0
    var annotations: [RuntimeAnnotationRecord] = []
}

final class RuntimeFunctionValueBox {
    let fnPtr: Int
    let closureRaw: Int
    let arity: Int
    let suspendEntryPoint: Int

    init(fnPtr: Int, closureRaw: Int, arity: Int, suspendEntryPoint: Int = 0) {
        self.fnPtr = fnPtr
        self.closureRaw = closureRaw
        self.arity = arity
        self.suspendEntryPoint = suspendEntryPoint
    }
}

// MARK: - RuntimeChildReferenceProviding conformances (ABI-004)
//
// These conformances enable the recursive BFS freeze in kk_freeze_object to
// traverse all reachable object references when freezing an object graph.
// Only types that store `Int` child handles need to conform.

extension RuntimeArrayBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { values.compactMap(\.childReferenceRawValue) }
}

extension RuntimePairBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        [firstValue, secondValue].compactMap(\.childReferenceRawValue)
            + (mutableMapRaw == 0 ? [] : [mutableMapRaw])
    }
}

extension RuntimeTripleBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        [firstValue, secondValue, thirdValue].compactMap(\.childReferenceRawValue)
    }
}
