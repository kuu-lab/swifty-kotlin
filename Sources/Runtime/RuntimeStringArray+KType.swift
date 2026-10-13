import Foundation
import RuntimeABI

// MARK: - REFL-005: KType and typeOf<T>()

// Source-backed KType properties are dispatched through the interface itable.
// Runtime-created KType boxes therefore register the same alphabetically sorted
// getter slots that the compiler assigns to the bundled KType declaration.
private let runtimeKTypeInterfaceTypeID: Int64 =
    runtimeStableNominalTypeID(fqName: "kotlin.reflect.KType")

private let runtimeKTypeArgumentsGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return __kk_ktype_arguments(raw)
}

private let runtimeKTypeClassifierGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return __kk_ktype_classifier(raw)
}

private let runtimeKTypeIsMarkedNullableGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return __kk_ktype_isMarkedNullable(raw)
}

func registerRuntimeObject(_ box: RuntimeKTypeBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject, typeID: kTypeRuntimeTypeID)
    _ = kk_object_register_itable_iface(raw, Int(runtimeKTypeInterfaceTypeID), 0)
    _ = kk_object_register_itable_method(
        raw, 0, 0, unsafeBitCast(runtimeKTypeArgumentsGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw, 0, 1, unsafeBitCast(runtimeKTypeClassifierGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw, 0, 2, unsafeBitCast(runtimeKTypeIsMarkedNullableGetter, to: Int.self)
    )
    return raw
}

private func runtimeKTypeCreate(_ classifierRaw: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    var argumentRaws: [Int] = []
    if argsRaw != 0 && argsRaw != runtimeNullSentinelInt,
       let ptr = UnsafeMutableRawPointer(bitPattern: argsRaw) {
        let isObj = runtimeStorage.withGCLock { state in
            state.objectPointers.contains(UInt(bitPattern: ptr))
        }
        if isObj, let listBox = tryCast(ptr, to: RuntimeListBox.self) {
            argumentRaws = listBox.elements
        }
    }
    let box = RuntimeKTypeBox(
        classifierRaw: classifierRaw,
        argumentRaws: argumentRaws,
        isMarkedNullable: isNullable != 0
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box)
}

/// KUU-1377: backs `KClassifier.createType` / `starProjectedType`.
@_cdecl("__kk_ktype_create")
public func __kk_ktype_create(_ classifierRaw: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    runtimeKTypeCreate(classifierRaw, argsRaw, isNullable)
}

/// Returns the classifier (KClass) raw handle from a KType, or null sentinel.
@_cdecl("__kk_ktype_classifier")
public func __kk_ktype_classifier(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return runtimeNullSentinelInt
    }
    return box.classifierRaw
}

/// Returns the list of type arguments (KTypeProjection handles) from a KType.
@_cdecl("__kk_ktype_arguments")
public func __kk_ktype_arguments(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.argumentRaws))
}

/// Returns 1 if the KType is marked nullable, 0 otherwise.
@_cdecl("__kk_ktype_isMarkedNullable")
public func __kk_ktype_isMarkedNullable(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return 0
    }
    return box.isMarkedNullable ? 1 : 0
}

/// Creates a KTypeProjection from a KType raw handle and variance ordinal.
/// variance: 0=IN, 1=OUT, 2=INVARIANT, -1=STAR (type is ignored for STAR)
@_cdecl("__kk_ktypeprojection_create")
public func __kk_ktypeprojection_create(_ typeRaw: Int, _ varianceOrdinal: Int) -> Int {
    let variance: RuntimeKVariance?
    if varianceOrdinal == -1 {
        variance = nil // STAR projection
    } else {
        variance = RuntimeKVariance(rawValue: varianceOrdinal) ?? .invariant
    }
    if variance == nil {
        return runtimeKTypeProjectionStar()
    }
    return runtimeKTypeProjectionCreate(typeRaw: typeRaw, variance: variance)
}

private func runtimeKTypeProjectionCreate(typeRaw: Int, variance: RuntimeKVariance?) -> Int {
    let box = RuntimeKTypeProjectionBox(typeRaw: typeRaw, variance: variance)
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box, typeID: kTypeProjectionRuntimeTypeID)
}

private func runtimeKTypeProjectionStar() -> Int {
    if let cached = runtimeStorage.withMetadataLock({ $0.kTypeProjectionStarRaw }) {
        return cached
    }
    registerReflectionRuntimeTypeMetadata()
    let candidate = registerRuntimeObject(
        RuntimeKTypeProjectionBox(typeRaw: 0, variance: nil),
        typeID: kTypeProjectionRuntimeTypeID
    )
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let cached = state.kTypeProjectionStarRaw {
            return cached
        }
        state.kTypeProjectionStarRaw = candidate
        return candidate
    }
    if winner != candidate {
        _ = runtimeReleaseObject(candidate)
    }
    return winner
}

/// Returns the canonical star projection used by the companion and `typeOf`.
@_cdecl("__kk_ktypeprojection_star")
public func __kk_ktypeprojection_star() -> Int {
    runtimeKTypeProjectionStar()
}

/// Creates a KTypeProjection through its public constructor.
/// The Kotlin constructor accepts either two nulls (a star projection) or
/// two non-null values; every other pair throws IllegalArgumentException.
@_cdecl("__kk_ktypeprojection_create_checked")
public func __kk_ktypeprojection_create_checked(
    _ varianceOrdinal: Int,
    _ typeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    let varianceIsNull = varianceOrdinal == runtimeNullSentinelInt
    let typeIsNull = typeRaw == 0 || typeRaw == runtimeNullSentinelInt
    // Nullable enum arguments cross the runtime ABI as boxed Int handles.
    // Preserve the null sentinel before unboxing; kk_unbox_int maps null to 0.
    let kotlinVarianceOrdinal = varianceIsNull ? -1 : kk_unbox_int(varianceOrdinal)
    // KVariance declares INVARIANT, IN, OUT, while RuntimeKVariance keeps the
    // existing typeOf bridge's internal order IN, OUT, INVARIANT.
    let decodedVarianceOrdinal: Int = switch kotlinVarianceOrdinal {
    case 0: 2 // INVARIANT
    case 1: 0 // IN
    case 2: 1 // OUT
    default: kotlinVarianceOrdinal
    }
    guard varianceIsNull == typeIsNull else {
        let message: String
        if varianceIsNull {
            message = "Star projection must have no type specified."
        } else {
            let varianceName: String = switch RuntimeKVariance(rawValue: decodedVarianceOrdinal) {
            case .in: "IN"
            case .out: "OUT"
            case .invariant: "INVARIANT"
            case nil: "INVARIANT"
            }
            message = "The projection variance \(varianceName) requires type to be specified."
        }
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: message)
        return 0
    }

    if varianceIsNull {
        return runtimeKTypeProjectionCreate(typeRaw: 0, variance: nil)
    }
    return runtimeKTypeProjectionCreate(
        typeRaw: typeRaw,
        variance: RuntimeKVariance(rawValue: decodedVarianceOrdinal) ?? .invariant
    )
}

/// Returns the Kotlin declaration ordinal for a projection's variance, or null.
@_cdecl("__kk_ktypeprojection_get_variance")
public func __kk_ktypeprojection_get_variance(_ projectionRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projectionRaw), let variance = box.variance else {
        return runtimeNullSentinelInt
    }
    switch variance {
    case .invariant:
        return 0
    case .in:
        return 1
    case .out:
        return 2
    }
}

/// Returns the projected KType handle, or null for a star projection.
@_cdecl("__kk_ktypeprojection_get_type")
public func __kk_ktypeprojection_get_type(_ projectionRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projectionRaw), box.typeRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return box.typeRaw
}

/// Implements `typeOf<T>()` — creates a KType for the given type token.
/// This is the reified inline function entry point. The compiler emits the
/// type token and nullability at the call site.
@_cdecl("kk_typeof")
public func kk_typeof(_ typeToken: Int, _ nameHint: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    let classifierRaw = __kk_kclass_create(typeToken, nameHint)
    return runtimeKTypeCreate(classifierRaw, argsRaw, isNullable)
}

// MARK: - KType / KTypeProjection Box Helpers

private func runtimeKTypeBox(from raw: Int) -> RuntimeKTypeBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKTypeBox.self)
    }
}

private func runtimeKTypeProjectionBox(from raw: Int) -> RuntimeKTypeProjectionBox? {
    guard raw != 0, raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return runtimeStorage.withGCLock { state in
        guard state.objectPointers.contains(UInt(bitPattern: ptr)) else {
            return nil
        }
        return tryCast(ptr, to: RuntimeKTypeProjectionBox.self)
    }
}
