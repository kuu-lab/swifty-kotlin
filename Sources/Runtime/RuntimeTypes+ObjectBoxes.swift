import Foundation

class RuntimeArrayBox {
    private final class Storage {
        var values: [RuntimeValue]
        var componentType: Int?
        var nativeBytes: UnsafeMutableBufferPointer<UInt8>?
        deinit { nativeBytes?.deallocate() }
        func pullBytes() {
            guard let bytes = nativeBytes else { return }
            for i in values.indices { values[i] = RuntimeValue(raw: Int(Int8(bitPattern: bytes[i]))) }
        }
        func pushBytes() {
            guard let bytes = nativeBytes else { return }
            precondition(bytes.count == values.count)
            for i in values.indices { bytes[i] = UInt8(truncatingIfNeeded: values[i].legacyRawValue) }
        }
        var viewHandles: [Int64: Int] = [:]
        let viewLock = NSLock()

        init(length: Int) {
            values = Array(repeating: RuntimeValue(raw: 0), count: max(0, length))
        }
    }

    private let storage: Storage

    var gcStorageID: ObjectIdentifier { ObjectIdentifier(storage) }

    private func mutateObjectFields(index: Int? = nil, _ mutation: () -> Void) {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        let owner = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
        let mutateByteStorage = runtimeStorage.withGCLock { state -> Bool in
            if storage.nativeBytes != nil {
                state.retainedArrayHeapFields.removeValue(forKey: ObjectIdentifier(storage))
                return true
            }
            mutation()
            if state.objectPointers.contains(owner) {
                state.arrayStorageByOwner[owner] = ObjectIdentifier(storage)
            }
            if let index {
                recordManagedHeapFieldLocked(index: index, state: &state)
            } else {
                recordManagedHeapFieldsLocked(owner: owner, state: &state)
            }
            return false
        }
        if mutateByteStorage { mutation() }
    }

    private func recordManagedHeapFieldLocked(index: Int, state: inout GCState) {
        let storageID = ObjectIdentifier(storage)
        if let raw = storage.values[index].childReferenceRawValue,
           state.heapObjects[UInt(bitPattern: raw)] != nil || state.objectPointers.contains(UInt(bitPattern: raw)) {
            if let roots = state.retainedArrayHeapFields[storageID], roots.storage === storage {
                roots.fields[index] = UInt(bitPattern: raw)
            } else {
                state.retainedArrayHeapFields[storageID] = RuntimeStorageHeapRoots(
                    storage: storage, fields: [index: UInt(bitPattern: raw)]
                )
            }
        } else {
            guard let roots = state.retainedArrayHeapFields[storageID],
                  roots.storage === storage else { return }
            roots.fields.removeValue(forKey: index)
            if roots.fields.isEmpty {
                state.retainedArrayHeapFields.removeValue(forKey: storageID)
            }
        }
    }

    func recordManagedHeapFieldsLocked(owner: UInt, state: inout GCState) {
        guard storage.nativeBytes == nil else { return }
        let storageID = ObjectIdentifier(storage)
        if state.objectPointers.contains(owner) {
            state.arrayStorageByOwner[owner] = storageID
        }
        var fields: [Int: UInt] = [:]
        for (index, value) in storage.values.enumerated() {
            if let raw = value.childReferenceRawValue,
               state.heapObjects[UInt(bitPattern: raw)] != nil || state.objectPointers.contains(UInt(bitPattern: raw)) {
                fields[index] = UInt(bitPattern: raw)
            }
        }
        if fields.isEmpty {
            state.retainedArrayHeapFields.removeValue(forKey: storageID)
        } else {
            state.retainedArrayHeapFields[storageID] = RuntimeStorageHeapRoots(storage: storage, fields: fields)
        }
    }

    /// The caller holds gcLock; reading the mirror avoids taking viewLock.
    func gcStorageChildRefsLocked(state: GCState) -> [Int] {
        guard let roots = state.retainedArrayHeapFields[ObjectIdentifier(storage)],
              roots.storage === storage else { return [] }
        return roots.fields.values.map { Int(bitPattern: $0) }
    }

    var values: [RuntimeValue] {
        get {
            storage.viewLock.lock()
            defer { storage.viewLock.unlock() }
            storage.pullBytes()
            return storage.values
        }
        set {
            mutateObjectFields {
                storage.values = newValue
                storage.pushBytes()
            }
        }
    }

    var elements: [Int] {
        get {
            storage.viewLock.lock()
            storage.pullBytes()
            let snapshot = storage.values
            storage.viewLock.unlock()
            return snapshot.map(\.legacyRawValue)
        }
        set {
            mutateObjectFields {
                storage.values = newValue.map { RuntimeValue(raw: $0) }
                storage.pushBytes()
            }
        }
    }

    subscript(index: Int) -> Int {
        get {
            storage.viewLock.lock()
            let value: RuntimeValue
            if let bytes = storage.nativeBytes {
                value = RuntimeValue(raw: Int(Int8(bitPattern: bytes[index])))
            } else {
                value = storage.values[index]
            }
            storage.viewLock.unlock()
            return value.legacyRawValue
        }
        set {
            mutateObjectFields(index: index) {
                if let bytes = storage.nativeBytes { bytes[index] = UInt8(truncatingIfNeeded: newValue) }
                storage.values[index] = RuntimeValue(
                    raw: newValue,
                    anyFallbackTag: storage.values[index].anyFallbackTag
                )
            }
        }
    }

    func value(at index: Int) -> RuntimeValue {
        if let bytes = storage.nativeBytes { return RuntimeValue(raw: Int(Int8(bitPattern: bytes[index]))) }
        return storage.values[index]
    }

    func setValue(_ value: Int, at index: Int, anyFallbackTag: Int32) {
        mutateObjectFields(index: index) {
            if let bytes = storage.nativeBytes { bytes[index] = UInt8(truncatingIfNeeded: value) }
            storage.values[index] = RuntimeValue(raw: value, anyFallbackTag: anyFallbackTag)
        }
    }

    func setValue(_ value: RuntimeValue, at index: Int) {
        mutateObjectFields(index: index) {
            if let bytes = storage.nativeBytes { bytes[index] = UInt8(truncatingIfNeeded: value.legacyRawValue) }
            storage.values[index] = runtimeValuePreservingAnyFallbackTag(value, existing: storage.values[index])
        }
    }

    func nativeByteAddress(at index: Int) -> UnsafeMutablePointer<UInt8>? {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        guard index >= 0, index < storage.values.count else { return nil }
        if storage.nativeBytes == nil {
            let bytes = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: storage.values.count)
            for (index, value) in storage.values.enumerated() {
                bytes[index] = UInt8(truncatingIfNeeded: value.legacyRawValue)
            }
            runtimeStorage.withGCLock { state in
                storage.nativeBytes = bytes
                state.retainedArrayHeapFields.removeValue(forKey: ObjectIdentifier(storage))
            }
        }
        return storage.nativeBytes?.baseAddress?.advanced(by: index)
    }

    var count: Int {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        return storage.values.count
    }

    init(length: Int) {
        storage = Storage(length: length)
    }

    private init(sharingStorageOf array: RuntimeArrayBox) {
        storage = array.storage
    }

    var componentType: Int? {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        return storage.componentType
    }

    func installComponentTypeIfAbsent(_ type: Int) {
        storage.viewLock.lock()
        defer { storage.viewLock.unlock() }
        if storage.componentType == nil { storage.componentType = type }
    }

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
    private let coroutineJobHandleLock = NSLock()
    private var storedCoroutineJobHandle: Int = 0
    var coroutineJobHandle: Int {
        withCoroutineJobHandle { $0 }
    }
    func withCoroutineJobHandle<Result>(_ body: (inout Int) -> Result) -> Result {
        coroutineJobHandleLock.lock()
        defer { coroutineJobHandleLock.unlock() }
        let oldValue = storedCoroutineJobHandle
        let result = body(&storedCoroutineJobHandle)
        if storedCoroutineJobHandle != oldValue {
            let owner = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
            runtimeStorage.withGCLock { state in
                if state.objectPointers.contains(owner), storedCoroutineJobHandle != 0 {
                    state.objectJobHandles[owner] = storedCoroutineJobHandle
                } else {
                    state.objectJobHandles.removeValue(forKey: owner)
                }
            }
        }
        return result
    }
    var backingListBox: RuntimeListBox?
    var backingSetBox: RuntimeSetBox?
    var backingMapBox: RuntimeMapBox?
    var backingMapRaw: Int = 0
    var throwableMessage: String?
    var throwableMessageRaw: Int = 0
    var throwableCause: Int
    var throwableCauseInitialized: Bool
    var throwableStackTraceAddresses: [Int]?
    var throwableStackTraceFrames: [RuntimeLogicalStackTraceFrame]?
    var throwableStackTraceElementsRaw: Int
    var throwableSuppressed: [Int]
    var throwableSuppressionEnabled: Bool
    var throwableWritableStackTrace: Bool
    var annotationReflectionMaterialized = false

    init(length: Int, classID: Int64) {
        self.classID = classID
        self.backingListBox = nil
        self.backingSetBox = nil
        self.backingMapBox = nil
        self.throwableMessage = nil
        self.throwableCause = 0
        self.throwableCauseInitialized = false
        self.throwableStackTraceAddresses = nil
        self.throwableStackTraceFrames = nil
        self.throwableStackTraceElementsRaw = 0
        self.throwableSuppressed = []
        self.throwableSuppressionEnabled = true
        self.throwableWritableStackTrace = true
        super.init(length: length)
    }
}

final class RuntimePairBox {
    let firstValue: RuntimeValue
    private(set) var secondValue: RuntimeValue
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

    func setSecondValue(_ value: RuntimeValue, returning previous: Int? = nil) {
        let threadID = runtimeGCCurrentThreadID()
        runtimeStorage.withGCLock { state in
            if let previous {
                runtimeRecordShadowHandoffLocked(previous, threadID: threadID, state: &state)
            }
            secondValue = value
            let owner = UInt(bitPattern: Unmanaged.passUnretained(self).toOpaque())
            if state.objectPointers.contains(owner) {
                recordRetainedBoxManagedHeapFieldsLocked(self, owner: owner, state: &state)
            }
        }
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
    let primitiveTypeBase: Int64

    var renderedString: String {
        if let enumEntryName {
            return enumEntryName
        }
        if primitiveTypeBase == RuntimeTypeTokenEncoding.uintBase {
            return String(UInt32(truncatingIfNeeded: value))
        }
        return String(value)
    }

    let anyFallbackTag: Int32

    let enumEntryName: String?
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

final class RuntimeUnitBox {}

final class RuntimeLongBox {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }
}

final class RuntimeULongBox {
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
    var returnTypeKTypeRaw: Int = 0
    var annotations: [RuntimeAnnotationRecord] = []
    var identityTargetRaw: Int = 0
    var identityCaptures: [Int] = []
    var getterAccessor: Int = 0
    var setterAccessor: Int = 0
}

struct RuntimeCallableAdapterIdentity {
    let samInterfaceTypeID: Int64
    let targetRaw: Int
    let returnTypeRaw: Int
    let arity: Int
    let isSuspend: Bool
    let modifierFlags: Int
    let captures: [Int]
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

extension RuntimeArrayBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] {
        let fieldRefs = values.compactMap(\.childReferenceRawValue)
        if let objectBox = self as? RuntimeObjectBox {
            let directRefs = [
                objectBox.coroutineJobHandle,
                objectBox.backingMapRaw,
                objectBox.throwableMessageRaw,
                objectBox.throwableCause,
                objectBox.throwableStackTraceElementsRaw,
            ] + objectBox.throwableSuppressed
            let nestedRefs = (objectBox.backingListBox?.childRefs ?? [])
                + (objectBox.backingSetBox?.childRefs ?? [])
                + (objectBox.backingMapBox?.childRefs ?? [])
            return fieldRefs + directRefs.filter { $0 != 0 } + nestedRefs
        }
        return fieldRefs
    }

    /// Array fields and job handles use mirrors to avoid nested locks.
    func gcChildRefsLocked(state: GCState) -> [Int] {
        var references = gcStorageChildRefsLocked(state: state)
        guard let objectBox = self as? RuntimeObjectBox else { return references }
        let owner = UInt(bitPattern: Unmanaged.passUnretained(objectBox).toOpaque())
        let directRefs = [
            state.objectJobHandles[owner] ?? 0,
            objectBox.backingMapRaw,
            objectBox.throwableMessageRaw,
            objectBox.throwableCause,
            objectBox.throwableStackTraceElementsRaw,
        ] + objectBox.throwableSuppressed
        references.append(contentsOf: directRefs.filter { $0 != 0 })
        references.append(contentsOf: objectBox.backingListBox?.gcChildRefsLocked(state: state) ?? [])
        references.append(contentsOf: objectBox.backingSetBox?.childRefs ?? [])
        references.append(contentsOf: objectBox.backingMapBox?.childRefs ?? [])
        return references
    }
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

extension RuntimeFunctionValueBox: RuntimeChildReferenceProviding {
    var childRefs: [Int] { closureRaw == 0 ? [] : [closureRaw] }
}
