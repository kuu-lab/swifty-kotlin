import Foundation

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

private let runtimeKTypeParameterIsReifiedGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return runtimeReflectionObject(from: raw, as: RuntimeKTypeParameterBox.self)?.isReified == true ? 1 : 0
}

private let runtimeKTypeParameterNameGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return runtimeReflectionObject(from: raw, as: RuntimeKTypeParameterBox.self)?.nameRaw ?? runtimeNullSentinelInt
}

private let runtimeKTypeParameterUpperBoundsGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    return runtimeReflectionObject(from: raw, as: RuntimeKTypeParameterBox.self)?.upperBoundsRaw
        ?? registerRuntimeObject(RuntimeListBox(elements: []))
}

private let runtimeKTypeParameterVarianceGetter: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw,
    outThrown in
    outThrown?.pointee = 0
    guard let box = runtimeReflectionObject(from: raw, as: RuntimeKTypeParameterBox.self) else {
        return runtimeNullSentinelInt
    }
    let names = ["INVARIANT", "IN", "OUT"]
    let ordinal = (0..<names.count).contains(box.varianceOrdinal) ? box.varianceOrdinal : 0
    return kk_enum_box_ordinal(
        ordinal,
        runtimeMakeStringRaw(names[ordinal]),
        Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KVariance"))
    )
}

private func registerRuntimeObject(_ box: RuntimeKTypeParameterBox) -> Int {
    let raw = registerRuntimeObject(box as AnyObject, typeID: kTypeParameterRuntimeTypeID)
    _ = kk_object_register_itable_iface(raw, Int(kTypeParameterRuntimeTypeID), 0)
    _ = kk_object_register_itable_method(
        raw, 0, 0, unsafeBitCast(runtimeKTypeParameterIsReifiedGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw, 0, 1, unsafeBitCast(runtimeKTypeParameterNameGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw, 0, 2, unsafeBitCast(runtimeKTypeParameterUpperBoundsGetter, to: Int.self)
    )
    _ = kk_object_register_itable_method(
        raw, 0, 3, unsafeBitCast(runtimeKTypeParameterVarianceGetter, to: Int.self)
    )
    return raw
}

func runtimeKTypeParameterHandle(
    identity: Int,
    name: String,
    varianceOrdinal: Int
) -> Int {
    let raw = __kk_ktypeparameter_create(
        identity,
        runtimeMakeStringRaw(name),
        varianceOrdinal,
        0
    )
    guard let box = runtimeReflectionObject(from: raw, as: RuntimeKTypeParameterBox.self),
          let bounds = runtimeReflectionObject(from: box.upperBoundsRaw, as: RuntimeListBox.self),
          bounds.elements.isEmpty
    else {
        return raw
    }
    let anyKClass = __kk_kclass_create(
        Int(RuntimeTypeTokenEncoding.anyBase),
        runtimeMakeStringRaw("kotlin.Any")
    )
    let anyType = registerRuntimeObject(RuntimeKTypeBox(
        classifierRaw: anyKClass,
        argumentRaws: [],
        isMarkedNullable: true
    ))
    let upperBounds = registerRuntimeObject(RuntimeListBox(elements: [anyType]))
    _ = __kk_ktypeparameter_set_upper_bounds(raw, upperBounds)
    return raw
}

@_cdecl("__kk_ktypeparameter_create")
public func __kk_ktypeparameter_create(
    _ identity: Int,
    _ nameRaw: Int,
    _ varianceOrdinal: Int,
    _ isReified: Int
) -> Int {
    if let cached = runtimeStorage.withMetadataLock({ $0.kTypeParameterCache[identity] }) {
        return cached
    }

    let bounds = registerRuntimeObject(RuntimeListBox(elements: []))
    let candidate = registerRuntimeObject(RuntimeKTypeParameterBox(
        nameRaw: nameRaw,
        varianceOrdinal: varianceOrdinal,
        isReified: isReified != 0,
        upperBoundsRaw: bounds
    ))
    registerReflectionRuntimeTypeMetadata()
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let cached = state.kTypeParameterCache[identity] {
            return cached
        }
        state.kTypeParameterCache[identity] = candidate
        return candidate
    }
    if winner != candidate {
        _ = runtimeReleaseObject(candidate)
    }
    return winner
}

@_cdecl("__kk_ktypeparameter_set_upper_bounds")
public func __kk_ktypeparameter_set_upper_bounds(_ parameterRaw: Int, _ boundsRaw: Int) -> Int {
    guard let parameter = runtimeReflectionObject(from: parameterRaw, as: RuntimeKTypeParameterBox.self) else {
        return 0
    }
    parameter.upperBoundsRaw = boundsRaw
    return 0
}

@_cdecl("__kk_ktypeparameter_is_runtime")
public func __kk_ktypeparameter_is_runtime(_ parameterRaw: Int) -> Int {
    runtimeReflectionObject(from: parameterRaw, as: RuntimeKTypeParameterBox.self) == nil ? 0 : 1
}

@_cdecl("__kk_ktypeparameter_get_name")
public func __kk_ktypeparameter_get_name(_ parameterRaw: Int) -> Int {
    runtimeReflectionObject(from: parameterRaw, as: RuntimeKTypeParameterBox.self)?.nameRaw
        ?? runtimeNullSentinelInt
}

private func runtimeKTypeCreate(
    _ classifierRaw: Int,
    _ argsRaw: Int,
    _ isNullable: Int,
    typeNameRaw: Int = 0
) -> Int {
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
    return runtimeKTypeCreate(
        classifierRaw,
        argumentRaws: argumentRaws,
        isMarkedNullable: isNullable != 0,
        typeNameRaw: typeNameRaw
    )
}

private func runtimeKTypeCreate(
    _ classifierRaw: Int,
    argumentRaws: [Int],
    isMarkedNullable: Bool,
    typeNameRaw: Int = 0
) -> Int {
    let box = RuntimeKTypeBox(
        classifierRaw: classifierRaw,
        argumentRaws: argumentRaws,
        isMarkedNullable: isMarkedNullable,
        typeNameRaw: typeNameRaw
    )
    registerReflectionRuntimeTypeMetadata()
    return registerRuntimeObject(box)
}

/// Copies a KType box, optionally overriding `isMarkedNullable`
/// (`isNullable < 0` keeps the source flag). The compiler emits this where a
/// reified `typeOf<T>`/`typeOf<T?>` reuses the type parameter's captured
/// KType: every `typeOf` evaluation must hand out a fresh box because
/// reference identity (`===`) is observable, and a `T?` use site adds
/// nullability the captured substitution may not carry.
@_cdecl("__kk_ktype_with_nullability")
public func __kk_ktype_with_nullability(_ ktypeRaw: Int, _ isNullable: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return ktypeRaw
    }
    return runtimeKTypeCreate(
        box.classifierRaw,
        argumentRaws: box.argumentRaws,
        isMarkedNullable: isNullable < 0 ? box.isMarkedNullable : isNullable != 0,
        typeNameRaw: box.typeNameRaw
    )
}

/// Derives the `__kk_array_component_type` descriptor equivalent to a KType
/// box: the classifier's nominal token plus, for `kotlin.Array`, the element
/// type's descriptor (mirroring `referenceArrayElementType` — `in`/`star`
/// projections collapse to `Any`). A `KTypeParameter` classifier resolves to
/// its first upper bound, matching the bound-erasure the descriptor path
/// used before this slot carried KTypes.
@_cdecl("__kk_ktype_component_descriptor")
public func __kk_ktype_component_descriptor(_ ktypeRaw: Int) -> Int {
    var visited = 0
    return runtimeKTypeComponentDescriptor(ktypeRaw, visited: &visited)
}

private func runtimeKTypeComponentDescriptor(_ raw: Int, visited: inout Int) -> Int {
    let anyDescriptor = __kk_array_component_type(Int(RuntimeTypeTokenEncoding.anyBase), 0)
    guard visited < 64, let box = runtimeKTypeBox(from: raw) else {
        return 0
    }
    visited += 1
    guard let kclass = runtimeKClassBox(from: box.classifierRaw) else {
        guard let parameter = runtimeReflectionObject(
            from: box.classifierRaw, as: RuntimeKTypeParameterBox.self
        ),
            let bounds = runtimeReflectionObject(
                from: parameter.upperBoundsRaw, as: RuntimeListBox.self
            ),
            let firstBound = bounds.elements.first
        else {
            return anyDescriptor
        }
        return runtimeKTypeComponentDescriptor(firstBound, visited: &visited)
    }
    var element = 0
    let token = Int64(truncatingIfNeeded: kclass.typeToken)
    let isKotlinArray = token & RuntimeTypeTokenEncoding.baseMask == RuntimeTypeTokenEncoding.nominalBase
        && (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
            == runtimeStableNominalTypeID(fqName: "kotlin.Array")
    if isKotlinArray {
        element = anyDescriptor
        if let projectionRaw = box.argumentRaws.first,
           let projection = runtimeKTypeProjectionBox(from: projectionRaw),
           projection.variance != .in,
           projection.typeRaw != 0
        {
            element = runtimeKTypeComponentDescriptor(projection.typeRaw, visited: &visited)
        }
    }
    return __kk_array_component_type(kclass.typeToken, element)
}

@_cdecl("__kk_ktype_create")
public func __kk_ktype_create(_ classifierRaw: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    runtimeKTypeCreate(classifierRaw, argsRaw, isNullable)
}

@_cdecl("__kk_ktype_classifier")
public func __kk_ktype_classifier(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return runtimeNullSentinelInt
    }
    return box.classifierRaw
}

@_cdecl("__kk_ktype_arguments")
public func __kk_ktype_arguments(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    return registerRuntimeObject(RuntimeListBox(elements: box.argumentRaws))
}

@_cdecl("__kk_ktype_isMarkedNullable")
public func __kk_ktype_isMarkedNullable(_ ktypeRaw: Int) -> Int {
    guard let box = runtimeKTypeBox(from: ktypeRaw) else {
        return 0
    }
    return box.isMarkedNullable ? 1 : 0
}

/// Distinguishes native KType boxes from source implementations of
/// KType so `KAnnotatedElement.annotations` reads can bypass the
/// interface getter (KUU-4068).
@_cdecl("__kk_ktype_is_runtime")
public func __kk_ktype_is_runtime(_ raw: Int) -> Int {
    runtimeKTypeBox(from: raw) == nil ? 0 : 1
}

/// Returns the annotations list for a KType as a RuntimeListBox.
/// Use-site type-annotation metadata is not yet emitted for runtime
/// KType boxes, so this returns an empty list; source-backed KType
/// implementations keep their own `annotations` through interface
/// dispatch.
@_cdecl("__kk_ktype_get_annotations_typed")
public func __kk_ktype_get_annotations_typed(_ raw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let records = runtimeKTypeBox(from: raw)?.annotations ?? []
    return runtimeAnnotationList(records, materializeFactories: true, outThrown: outThrown)
}

/// variance: 0=IN, 1=OUT, 2=INVARIANT, -1=STAR (type is ignored for STAR)
@_cdecl("__kk_ktypeprojection_create")
public func __kk_ktypeprojection_create(_ typeRaw: Int, _ varianceOrdinal: Int) -> Int {
    let variance: RuntimeKVariance?
    if varianceOrdinal == -1 {
        variance = nil
    } else {
        variance = RuntimeKVariance(rawValue: varianceOrdinal) ?? .invariant
    }
    if variance == nil {
        return runtimeKTypeProjectionStar()
    }
    return runtimeKTypeProjectionCreate(typeRaw: typeRaw, variance: variance)
}

func runtimeKTypeProjectionCreate(typeRaw: Int, variance: RuntimeKVariance?) -> Int {
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

/// Returns the projection's variance as a `kotlin.reflect.KVariance` enum box
/// (the canonical `kk_enum_box_ordinal` handle, like the KTypeParameter and
/// KClass visibility getters), or the null sentinel for a star projection.
/// A `KVariance?` slot must carry the box-or-sentinel form: a raw ordinal
/// would reach erased `==`/`===` slots unboxed and compare unequal to the
/// same entry's tagged singleton box (KUU-3814).
@_cdecl("__kk_ktypeprojection_get_variance")
public func __kk_ktypeprojection_get_variance(_ projectionRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projectionRaw), let variance = box.variance else {
        return runtimeNullSentinelInt
    }
    let names = ["INVARIANT", "IN", "OUT"]
    let ordinal: Int = switch variance {
    case .invariant:
        0
    case .in:
        1
    case .out:
        2
    }
    return kk_enum_box_ordinal(
        ordinal,
        runtimeMakeStringRaw(names[ordinal]),
        Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KVariance"))
    )
}

@_cdecl("__kk_ktypeprojection_get_type")
public func __kk_ktypeprojection_get_type(_ projectionRaw: Int) -> Int {
    guard let box = runtimeKTypeProjectionBox(from: projectionRaw), box.typeRaw != 0 else {
        return runtimeNullSentinelInt
    }
    return box.typeRaw
}

/// KUU-3895: unknown-base tokens all encode to 0, so a token-0 KClass box
/// cannot trust the token-keyed metadata registry (Kotlin `Nothing` eagerly
/// registers its `java.lang.Void` entry under token 0) — the KType must
/// carry its own Kotlin type name. `Nothing` is also the only type whose
/// *type* name (`kotlin.Nothing`) differs from its *classifier* hint
/// (`java.lang.Void` — `Nothing::class` really is `Void::class`), so the
/// hint is remapped for it alone; a Java `Void` type arrives through a
/// nominal token and keeps its own name.
private func runtimeAmbiguousKTypeName(typeToken: Int, nameHint: Int) -> Int {
    guard Int64(truncatingIfNeeded: typeToken) & RuntimeTypeTokenEncoding.baseMask == 0,
          nameHint != 0,
          nameHint != runtimeNullSentinelInt,
          let hint = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint)),
          !hint.isEmpty
    else {
        return 0
    }
    return runtimeMakeStringRaw(hint == "java.lang.Void" ? "kotlin.Nothing" : hint)
}

/// The compiler emits the type token and nullability at the call site.
@_cdecl("kk_typeof")
public func kk_typeof(_ typeToken: Int, _ nameHint: Int, _ argsRaw: Int, _ isNullable: Int) -> Int {
    let classifierRaw = __kk_kclass_create(typeToken, nameHint)
    return runtimeKTypeCreate(
        classifierRaw,
        argsRaw,
        isNullable,
        typeNameRaw: runtimeAmbiguousKTypeName(typeToken: typeToken, nameHint: nameHint)
    )
}

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
