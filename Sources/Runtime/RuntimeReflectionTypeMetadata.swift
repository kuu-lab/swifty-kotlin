import Foundation

// Stable nominal IDs for runtime-backed kotlin.reflect values.
//
// The compiler's nominal type tokens use the same FNV-1a-derived IDs. Keeping
// the IDs in one runtime-owned table lets reflection handles participate in
// `is`/`as` checks without depending on allocation order.
let kCallableRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KCallable")
let kFunctionRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction")
let kConstructorRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KConstructor")
let kPropertyRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty")
let kMutablePropertyRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty")
let kProperty0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty0")
let kProperty1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty1")
let kProperty2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KProperty2")
let kMutableProperty0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty0")
let kMutableProperty1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty1")
let kMutableProperty2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KMutableProperty2")
let kFunction0RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction0")
let kFunction1RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction1")
let kFunction2RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction2")
let kFunction3RuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction3")
let kClassifierRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KClassifier")
let kClassRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KClass")
let kTypeRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KType")
let kTypeParameterRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KTypeParameter")
let kTypeProjectionRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KTypeProjection")
let kParameterRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KParameter")

/// Out-buffer matching the emitted `{i8*, i64, i64, i64}` String aggregate
/// ABI: itable-dispatched String members are invoked through the flat
/// convention, so the first argument is the caller's sret buffer.
private struct RuntimeKCallableFlatStringOut {
    var data: Int = 0
    var length: Int = 0
    var byteCount: Int = 0
    var hash: Int = 0
}

/// Whether `value` could be the receiver of a KCallable itable call: a
/// registered object carrying the KCallable interface slot, or a compiler-
/// tagged callable reference.
private func runtimeKCallableIsReceiver(_ value: Int) -> Bool {
    if runtimeRegisteredInterfaceSlot(objectRaw: value, interfaceTypeID: kCallableRuntimeTypeID) != nil {
        return true
    }
    return runtimeStorage.withDelegateLock { state in
        state.callableRefMetadataByValue[value] != nil
    }
}

/// Dual-ABI shim. `property.name` call sites emit either the erased Int
/// convention (arg0 = receiver, arg1 = outThrown) or the flat String
/// aggregate convention (arg0 = sret out-buffer, arg1 = receiver,
/// arg2 = outThrown), depending on which callee signature the emitter
/// resolved for the synthetic accessor. The receiver is always a registered
/// object or tagged callable ref, so identify which argument carries it.
private let runtimeKCallableNameGetter: @convention(c) (
    Int,
    Int,
    UnsafeMutablePointer<Int>?
) -> Int = { arg0, arg1, arg2 in
    if !runtimeKCallableIsReceiver(arg0), runtimeKCallableIsReceiver(arg1) {
        // Flat String-aggregate convention: arg0 is the caller's sret buffer.
        arg2?.pointee = 0
        let nameRaw = __kk_kcallable_get_name(arg1)
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = kk_string_to_flat(nameRaw, &length, &byteCount, &hash)
        if let out = UnsafeMutableRawPointer(bitPattern: arg0) {
            let flat = out.assumingMemoryBound(to: RuntimeKCallableFlatStringOut.self)
            flat.pointee.data = data.map { Int(bitPattern: $0) } ?? 0
            flat.pointee.length = length
            flat.pointee.byteCount = byteCount
            flat.pointee.hash = hash
        }
        return arg0
    }
    // Erased Int convention: arg0 = receiver, arg1 = outThrown.
    UnsafeMutablePointer<Int>(bitPattern: arg1)?.pointee = 0
    return __kk_kcallable_get_name(arg0)
}

private let runtimeKCallableReturnTypeGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return __kk_kcallable_get_return_type(raw)
}

/// Registers runtime reflection values for KCallable's source-backed property
/// getters. User implementations and these runtime values then share interface
/// dispatch, while the bridge getters preserve the metadata-backed behavior.
func runtimeRegisterKCallableItableIfNeeded(rawValue: Int, typeID: Int64) {
    let callableTypeIDs: Set<Int64> = [
        kCallableRuntimeTypeID,
        kFunctionRuntimeTypeID,
        kConstructorRuntimeTypeID,
        kPropertyRuntimeTypeID,
        kMutablePropertyRuntimeTypeID,
        kProperty0RuntimeTypeID,
        kProperty1RuntimeTypeID,
        kProperty2RuntimeTypeID,
        kMutableProperty0RuntimeTypeID,
        kMutableProperty1RuntimeTypeID,
        kMutableProperty2RuntimeTypeID,
        kFunction0RuntimeTypeID,
        kFunction1RuntimeTypeID,
        kFunction2RuntimeTypeID,
        kFunction3RuntimeTypeID,
    ]
    guard callableTypeIDs.contains(typeID) else { return }

    let interfaceSlot = 0
    _ = kk_object_register_itable_iface(rawValue, Int(kCallableRuntimeTypeID), interfaceSlot)
    _ = kk_object_register_itable_method(
        rawValue, interfaceSlot, 0, unsafeBitCast(runtimeKCallableNameGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        rawValue, interfaceSlot, 1, unsafeBitCast(runtimeKCallableReturnTypeGetter, to: Int.self)
    )
}

private let reflectionRuntimeTypeMetadataEdges: [(Int64, Int64)] = [
    (kFunctionRuntimeTypeID, kCallableRuntimeTypeID),
    (kConstructorRuntimeTypeID, kFunctionRuntimeTypeID),
    (kPropertyRuntimeTypeID, kCallableRuntimeTypeID),
    (kMutablePropertyRuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty0RuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty1RuntimeTypeID, kPropertyRuntimeTypeID),
    (kProperty2RuntimeTypeID, kPropertyRuntimeTypeID),
    (kMutableProperty0RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty0RuntimeTypeID, kProperty0RuntimeTypeID),
    (kMutableProperty1RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty1RuntimeTypeID, kProperty1RuntimeTypeID),
    (kMutableProperty2RuntimeTypeID, kMutablePropertyRuntimeTypeID),
    (kMutableProperty2RuntimeTypeID, kProperty2RuntimeTypeID),
    (kFunction0RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction1RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction2RuntimeTypeID, kFunctionRuntimeTypeID),
    (kFunction3RuntimeTypeID, kFunctionRuntimeTypeID),
    (kClassRuntimeTypeID, kClassifierRuntimeTypeID),
    (kTypeRuntimeTypeID, kClassifierRuntimeTypeID),
    (kTypeParameterRuntimeTypeID, kClassifierRuntimeTypeID),
]

/// Registers the reflection hierarchy before a handle is tagged. The edges are
/// static, so they are inserted once; the flag is cleared with `typeParents`
/// when test isolation resets metadata, which triggers re-registration.
@inline(__always)
func registerReflectionRuntimeTypeMetadata() {
    runtimeStorage.withMetadataLock { state in
        if state.reflectionTypeEdgesRegistered {
            return
        }
        for (childTypeID, parentTypeID) in reflectionRuntimeTypeMetadataEdges {
            var parents = state.typeParents[childTypeID] ?? []
            parents.insert(parentTypeID)
            state.typeParents[childTypeID] = parents
        }
        state.reflectionTypeEdgesRegistered = true
    }
}

/// Returns a live runtime reflection box of the requested Swift type.
func runtimeReflectionObject<T: AnyObject>(from raw: Int, as type: T.Type) -> T? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else {
        return nil
    }
    let isObjectPointer = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isObjectPointer else {
        return nil
    }
    return tryCast(ptr, to: type)
}

/// Shared KCallable.name dispatch for every runtime reflection box returned by
/// KClass member and constructor queries.
@_cdecl("__kk_kcallable_get_name")
public func __kk_kcallable_get_name(_ callableRaw: Int) -> Int {
    if let taggedName = runtimeStorage.withDelegateLock({ state in
        state.callableRefMetadataByValue[callableRaw]?.nameRaw
    }) {
        return taggedName
    }
    if let function = runtimeReflectionObject(from: callableRaw, as: RuntimeKFunctionBox.self) {
        return function.nameRaw
    }
    if let constructor = runtimeReflectionObject(from: callableRaw, as: RuntimeKConstructorBox.self) {
        return constructor.nameRaw
    }
    if let property = runtimeReflectionObject(from: callableRaw, as: RuntimeKPropertyStub.self) {
        return property.name
    }
    return runtimeNullSentinelInt
}

/// Shared KCallable.returnType dispatch for runtime reflection boxes and
/// compiler-tagged callable references.
@_cdecl("__kk_kcallable_get_return_type")
public func __kk_kcallable_get_return_type(_ callableRaw: Int) -> Int {
    let returnTypeRaw: Int?
    if let taggedReturnType = runtimeStorage.withDelegateLock({ state in
        state.callableRefMetadataByValue[callableRaw]?.returnTypeRaw
    }) {
        returnTypeRaw = taggedReturnType
    } else if let function = runtimeReflectionObject(from: callableRaw, as: RuntimeKFunctionBox.self) {
        returnTypeRaw = function.returnTypeRaw
    } else if let constructor = runtimeReflectionObject(from: callableRaw, as: RuntimeKConstructorBox.self) {
        returnTypeRaw = constructor.returnTypeRaw
    } else if let property = runtimeReflectionObject(from: callableRaw, as: RuntimeKPropertyStub.self) {
        returnTypeRaw = property.returnType
    } else {
        returnTypeRaw = nil
    }

    guard let returnTypeRaw,
          returnTypeRaw != 0,
          returnTypeRaw != runtimeNullSentinelInt,
          extractString(from: UnsafeMutableRawPointer(bitPattern: returnTypeRaw)) != nil
    else {
        return runtimeNullSentinelInt
    }

    // The metadata fields predate RuntimeKTypeBox and store a KKString
    // descriptor. Box that descriptor at the KCallable boundary so the
    // source-level return type is an actual KType value.
    let typeName = extractString(from: UnsafeMutableRawPointer(bitPattern: returnTypeRaw)) ?? ""
    let box = RuntimeKTypeBox(
        classifierRaw: __kk_kclass_create(0, returnTypeRaw),
        argumentRaws: [],
        isMarkedNullable: typeName.hasSuffix("?"),
        typeNameRaw: returnTypeRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kTypeRuntimeTypeID)
}
