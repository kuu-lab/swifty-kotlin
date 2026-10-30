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
/// Stable nominal IDs for the arity-specific `KFunctionN`/`KSuspendFunctionN`
/// reflection interfaces (KUU-3841). Both families are compiler-synthesized on
/// the JVM with no distinct runtime class, so `x is KFunctionN` and
/// `x is KSuspendFunctionN` erase to a plain `instanceof KFunction` regardless
/// of arity or suspend-ness — verified against kotlinc output.
let kFunctionArityRuntimeTypeIDs: [Int64] = (0 ... 22).map {
    runtimeStableNominalTypeID(fqName: "kotlin.reflect.KFunction\($0)")
}
let kSuspendFunctionArityRuntimeTypeIDs: [Int64] = (0 ... 22).map {
    runtimeStableNominalTypeID(fqName: "kotlin.reflect.KSuspendFunction\($0)")
}

/// Whether `typeID` is the nominal payload of an arity-specific KFunctionN or
/// KSuspendFunctionN token. Values carrying a KFunction identity satisfy every
/// such payload (see the JVM erasure note above).
func runtimeIsKFunctionArityTypeID(_ typeID: Int64) -> Bool {
    kFunctionArityRuntimeTypeIDs.contains(typeID)
        || kSuspendFunctionArityRuntimeTypeIDs.contains(typeID)
}
let kClassifierRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KClassifier")
let kAnnotatedElementRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KAnnotatedElement")
let kDeclarationContainerRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.reflect.KDeclarationContainer")
let kotlinFunctionRuntimeTypeID = runtimeStableNominalTypeID(fqName: "kotlin.Function")
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
///
/// The flat branch only matches x86-64 SysV, where LLVM demotes the
/// `{ptr, i64, i64, i64}` return to a hidden first-argument pointer. AArch64
/// returns that aggregate in x0-x3, which this shim cannot produce, so the
/// compiler reads `KCallable.name` for runtime values through
/// `__kk_kcallable_get_name` before falling back to interface dispatch
/// (`emitRuntimeKCallableNameFastPath`), so interface property reads of
/// runtime values never reach this shim.
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
    let callableTypeIDs: Set<Int64> = Set(
        [
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
        ]
            + kFunctionArityRuntimeTypeIDs
            + kSuspendFunctionArityRuntimeTypeIDs
    )
    guard callableTypeIDs.contains(typeID) else { return }

    // Source-backed callable-reference wrappers register their interface
    // closure in generated code. Reuse KCallable's actual slot when present:
    // always using slot zero can alias KProperty1.get in a KLIB consumer and
    // replace it with the KCallable.call bridge.
    let interfaceSlot: Int
    if let registeredSlot = runtimeRegisteredInterfaceSlot(
        objectRaw: rawValue,
        interfaceTypeID: kCallableRuntimeTypeID
    ) {
        interfaceSlot = registeredSlot
    } else {
        interfaceSlot = 0
        _ = kk_object_register_itable_iface(rawValue, Int(kCallableRuntimeTypeID), interfaceSlot)
    }
    if typeID == kProperty0RuntimeTypeID || typeID == kMutableProperty0RuntimeTypeID {
        _ = kk_object_register_itable_iface(rawValue, Int(kProperty0RuntimeTypeID), interfaceSlot)
    }
    _ = kk_object_register_itable_method(
        rawValue, interfaceSlot, 7, unsafeBitCast(runtimeKCallableNameGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        rawValue, interfaceSlot, 9, unsafeBitCast(runtimeKCallableReturnTypeGetter, to: Int.self)
    )
    let call: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, arguments, thrown in
        __kk_kcallable_call(raw, arguments, thrown)
    }
    let callBy: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = { raw, arguments, thrown in
        __kk_kcallable_call_by(raw, arguments, thrown)
    }
    _ = kk_object_register_itable_method(rawValue, interfaceSlot, 0, unsafeBitCast(call, to: Int.self))
    _ = kk_object_register_itable_method(rawValue, interfaceSlot, 1, unsafeBitCast(callBy, to: Int.self))
}

private let reflectionRuntimeTypeMetadataEdges: [(Int64, Int64)] = {
    var edges: [(Int64, Int64)] = [
        // Source-declared supertypes (Stdlib/kotlin/reflect): KCallable and KClass
        // extend KAnnotatedElement, KClass extends KDeclarationContainer, and
        // KFunction extends kotlin.Function.
        (kCallableRuntimeTypeID, kAnnotatedElementRuntimeTypeID),
        (kFunctionRuntimeTypeID, kCallableRuntimeTypeID),
        (kFunctionRuntimeTypeID, kotlinFunctionRuntimeTypeID),
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
        (kClassRuntimeTypeID, kClassifierRuntimeTypeID),
        (kClassRuntimeTypeID, kAnnotatedElementRuntimeTypeID),
        (kClassRuntimeTypeID, kDeclarationContainerRuntimeTypeID),
        (kTypeRuntimeTypeID, kClassifierRuntimeTypeID),
        (kTypeParameterRuntimeTypeID, kClassifierRuntimeTypeID),
    ]
    // The bundled declarations mirror the synthesized hierarchies:
    // KFunctionN : KFunction<R>, FunctionN<P..., R> and
    // KSuspendFunctionN : KFunction<R>, SuspendFunctionN<P..., R>.
    for arity in 0 ... 22 {
        edges.append((kFunctionArityRuntimeTypeIDs[arity], kFunctionRuntimeTypeID))
        edges.append((
            kFunctionArityRuntimeTypeIDs[arity],
            runtimeStableNominalTypeID(fqName: "kotlin.Function.Function\(arity)")
        ))
        edges.append((kSuspendFunctionArityRuntimeTypeIDs[arity], kFunctionRuntimeTypeID))
        edges.append((
            kSuspendFunctionArityRuntimeTypeIDs[arity],
            runtimeStableNominalTypeID(fqName: "kotlin.coroutines.SuspendFunction\(arity)")
        ))
    }
    return edges
}()

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

@_cdecl("__kk_kcallable_get_return_type")
public func __kk_kcallable_get_return_type(_ callableRaw: Int) -> Int {
    let returnTypeKTypeRaw: Int?
    if let metadata = runtimeStorage.withDelegateLock({ $0.callableRefMetadataByValue[callableRaw] }) {
        returnTypeKTypeRaw = metadata.returnTypeKTypeRaw
    } else if let property = runtimeReflectionObject(from: callableRaw, as: RuntimeKPropertyStub.self) {
        returnTypeKTypeRaw = property.returnTypeKTypeRaw
    } else {
        returnTypeKTypeRaw = nil
    }
    if let returnTypeKTypeRaw,
       returnTypeKTypeRaw != 0,
       returnTypeKTypeRaw != runtimeNullSentinelInt {
        return returnTypeKTypeRaw
    }

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
