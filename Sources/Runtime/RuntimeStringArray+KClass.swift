import Foundation

@_cdecl("__kk_type_token_simple_name")
public func __kk_type_token_simple_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    // KUU-1084: function-type names derive from the token payload itself so
    // they stay stable regardless of which call site interned the KClass or
    // what name hint it passed.
    if base == RuntimeTypeTokenEncoding.functionBase {
        let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
        let (arity, isSuspend) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
        let name = isSuspend ? "SuspendFunction\(arity)" : "Function\(arity)"
        let utf8 = Array(name.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }
    if let name = runtimeRangeClassQualifiedName(typeToken: typeToken),
       let simpleName = name.split(separator: ".").last {
        return runtimeMakeStringRaw(String(simpleName))
    }
    // Class literals carry the qualified name so reflection works even when
    // no class metadata has been registered. Keep simpleName unqualified.
    if nameHint != 0, nameHint != runtimeNullSentinelInt {
        if let hint = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint)),
           let name = hint.split(separator: ".").last {
            return runtimeMakeStringRaw(String(name))
        }
        return nameHint
    }
    let name = runtimeBuiltinTokenSimpleName(base) ?? "Unknown"
    let utf8 = Array(name.utf8)
    return utf8.withUnsafeBufferPointer { buf in
        Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
    }
}

/// Simple names of the builtin type-token bases; their qualified names are
/// `kotlin.` + the simple name.
private func runtimeBuiltinTokenSimpleName(_ base: Int64) -> String? {
    switch base {
    case RuntimeTypeTokenEncoding.anyBase:
        "Any"
    case RuntimeTypeTokenEncoding.stringBase:
        "String"
    case RuntimeTypeTokenEncoding.intBase:
        "Int"
    case RuntimeTypeTokenEncoding.uintBase:
        "UInt"
    case RuntimeTypeTokenEncoding.ulongBase:
        "ULong"
    case RuntimeTypeTokenEncoding.ubyteBase:
        "UByte"
    case RuntimeTypeTokenEncoding.ushortBase:
        "UShort"
    case RuntimeTypeTokenEncoding.byteBase:
        "Byte"
    case RuntimeTypeTokenEncoding.shortBase:
        "Short"
    case RuntimeTypeTokenEncoding.booleanBase:
        "Boolean"
    case RuntimeTypeTokenEncoding.longBase:
        "Long"
    case RuntimeTypeTokenEncoding.doubleBase:
        "Double"
    case RuntimeTypeTokenEncoding.floatBase:
        "Float"
    case RuntimeTypeTokenEncoding.charBase:
        "Char"
    case RuntimeTypeTokenEncoding.nullBase:
        "Nothing"
    case RuntimeTypeTokenEncoding.unitBase:
        "Unit"
    default:
        nil
    }
}

private func runtimeKClassQualifiedName(_ name: String) -> String {
    // This Kotlin platform classifier is a JVM typealias. Keep the Kotlin
    // type identity in metadata, but expose the JVM reflection name.
    name == "kotlin.RuntimeException" ? "java.lang.RuntimeException" : name
}

/// For nominal (user-defined) types registered metadata takes precedence over
/// the compiler-supplied qualified name hint.
@_cdecl("__kk_type_token_qualified_name")
public func __kk_type_token_qualified_name(_ typeToken: Int, _ nameHint: Int) -> Int {
    let token = Int64(truncatingIfNeeded: typeToken)
    let base = token & RuntimeTypeTokenEncoding.baseMask
    let payload = (token >> RuntimeTypeTokenEncoding.payloadShift) & RuntimeTypeTokenEncoding.payloadMask
    let (functionArity, isSuspendFunction) = RuntimeTypeTokenEncoding.functionPayloadParts(payload)
    let qualifiedName: String? = if base == RuntimeTypeTokenEncoding.functionBase {
        isSuspendFunction
            ? "kotlin.coroutines.intrinsics.SuspendFunction\(functionArity)"
            : "kotlin.Function\(functionArity)"
    } else {
        runtimeBuiltinTokenSimpleName(base).map { "kotlin." + $0 }
    }
    if let qualifiedName {
        let utf8 = Array(qualifiedName.utf8)
        return utf8.withUnsafeBufferPointer { buf in
            Int(bitPattern: kk_string_from_utf8(buf.baseAddress!, Int32(buf.count)))
        }
    }
    if let name = runtimeRangeClassQualifiedName(typeToken: typeToken) {
        return runtimeMakeStringRaw(name)
    }
    if base == RuntimeTypeTokenEncoding.nominalBase,
       let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    {
        if metadata.isLocal {
            return runtimeNullSentinelInt
        }
        return runtimeMakeStringRaw(runtimeKClassQualifiedName(metadata.qualifiedName))
    }
    if nameHint != 0, nameHint != runtimeNullSentinelInt {
        if let hint = extractString(from: UnsafeMutableRawPointer(bitPattern: nameHint)) {
            return runtimeMakeStringRaw(runtimeKClassQualifiedName(hint))
        }
        return nameHint
    }
    return __kk_type_token_simple_name(typeToken, nameHint)
}

func runtimeKClassBox(from raw: Int) -> RuntimeKClassBox? {
    resolveRuntimeHandle(raw, as: RuntimeKClassBox.self)
}

/// KClass boxes are interned: repeated calls with the same `typeToken`
/// return the same pointer without allocating a new box. This avoids
/// unbounded memory growth when `T::class` is evaluated in a loop.
@_cdecl("__kk_kclass_create")
public func __kk_kclass_create(_ typeToken: Int, _ nameHint: Int) -> Int {
    let cacheKey = KClassCacheKey(typeToken: typeToken)
    if let cached = runtimeStorage.withMetadataLock({ state in state.kClassBoxCache[cacheKey] }) {
        return cached
    }
    let box = RuntimeKClassBox(typeToken: typeToken, nameHint: nameHint)
    registerReflectionRuntimeTypeMetadata()
    let result = registerRuntimeObject(box, typeID: kClassRuntimeTypeID)
    let winner = runtimeStorage.withMetadataLock { state -> Int in
        if let existing = state.kClassBoxCache[cacheKey] {
            return existing
        }
        state.kClassBoxCache[cacheKey] = result
        return result
    }
    if winner != result {
        _ = runtimeReleaseObject(result)
    }
    return winner
}

@_cdecl("__kk_kclass_of")
public func __kk_kclass_of(_ value: Int, _ fallbackToken: Int, _ nameHint: Int) -> Int {
    if let ptr = UnsafeMutableRawPointer(bitPattern: value),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }),
       let annotation = tryCast(ptr, to: RuntimeAnnotationBox.self) {
        if annotation.annotationClassRaw != 0 {
            return annotation.annotationClassRaw
        }
        // Reflected annotations are metadata boxes rather than nominal objects.
        // Recover their declared class identity instead of the static Annotation bound.
        let typeID = runtimeStableNominalTypeID(fqName: annotation.annotationFQName)
        let token = (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase
        return __kk_kclass_create(Int(truncatingIfNeeded: token), runtimeMakeStringRaw(annotation.annotationFQName))
    }
    // Unit stays as the raw zero value when it crosses an erased Any boundary;
    // other erased primitives are boxed. Recover Unit before falling back to
    // the statically supplied Any token, while preserving raw Boolean/Int zero.
    let fallbackBase = Int64(truncatingIfNeeded: fallbackToken) & RuntimeTypeTokenEncoding.baseMask
    if value == 0, fallbackBase == RuntimeTypeTokenEncoding.anyBase {
        return __kk_kclass_create(Int(RuntimeTypeTokenEncoding.unitBase), 0)
    }
    if runtimeArrayBoxExcludingObjects(from: value) != nil,
       let arrayClass = runtimeArrayKClassIdentity(rawValue: value)
    {
        return __kk_kclass_create(arrayClass.typeToken, arrayClass.nameHint)
    }
    if let typeID = runtimeObjectTypeID(rawValue: value) {
        let token = (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
            | RuntimeTypeTokenEncoding.nominalBase
        return __kk_kclass_create(Int(truncatingIfNeeded: token), 0)
    }
    if let ptr = UnsafeMutableRawPointer(bitPattern: value),
       runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: ptr)) }) {
        // Range factories retain their classifier in the kind tag, not nominal
        // object metadata. Supply its name even before reflection registration.
        if let range = tryCast(ptr, to: RuntimeRangeBox.self) {
            let typeID = runtimeRangeBoxNominalTypeID(range.kind)
            let token = (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                | RuntimeTypeTokenEncoding.nominalBase
            return __kk_kclass_create(Int(truncatingIfNeeded: token), runtimeMakeStringRaw(range.kind.qualifiedName))
        }
        // Runtime-created throwables are boxes without nominal object tags.
        // Their declared exception identity must override the catch variable's type.
        if let throwable = tryCast(ptr, to: RuntimeThrowableBox.self) {
            let typeID = runtimeStableNominalTypeID(fqName: throwable.exceptionFQName)
            let token = (typeID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                | RuntimeTypeTokenEncoding.nominalBase
            let displayName = runtimeJVMExceptionFQName(from: throwable.exceptionFQName)
            return __kk_kclass_create(Int(truncatingIfNeeded: token), runtimeMakeStringRaw(displayName))
        }
        let base: Int64?
        if let box = tryCast(ptr, to: RuntimeIntBox.self) {
            if let enumID = box.enumClassID {
                let token = (enumID & RuntimeTypeTokenEncoding.payloadMask) << RuntimeTypeTokenEncoding.payloadShift
                    | RuntimeTypeTokenEncoding.nominalBase
                return __kk_kclass_create(Int(truncatingIfNeeded: token), 0)
            }
            base = box.primitiveTypeBase
        } else if tryCast(ptr, to: RuntimeStringBox.self) != nil {
            base = RuntimeTypeTokenEncoding.stringBase
        } else if tryCast(ptr, to: RuntimeLongBox.self) != nil {
            base = RuntimeTypeTokenEncoding.longBase
        } else if tryCast(ptr, to: RuntimeULongBox.self) != nil {
            base = RuntimeTypeTokenEncoding.ulongBase
        } else if tryCast(ptr, to: RuntimeDoubleBox.self) != nil {
            base = RuntimeTypeTokenEncoding.doubleBase
        } else if tryCast(ptr, to: RuntimeFloatBox.self) != nil {
            base = RuntimeTypeTokenEncoding.floatBase
        } else if tryCast(ptr, to: RuntimeCharBox.self) != nil {
            base = RuntimeTypeTokenEncoding.charBase
        } else if tryCast(ptr, to: RuntimeBoolBox.self) != nil {
            base = RuntimeTypeTokenEncoding.booleanBase
        } else if tryCast(ptr, to: RuntimeUnitBox.self) != nil {
            base = RuntimeTypeTokenEncoding.unitBase
        } else {
            base = nil
        }
        if let base {
            return __kk_kclass_create(Int(base), 0)
        }
    }
    return __kk_kclass_create(fallbackToken, nameHint)
}

// Unlike `__kk_type_token_simple_name`/`__kk_type_token_qualified_name` (which take
// a bare type token + name hint known at the `T::class` call site), these take
// the KClass box handle itself so the Kotlin-source `simpleName`/`qualifiedName`
// properties (Sources/CompilerCore/Stdlib/kotlin/reflect/KClasses.kt) can
// be ordinary extension properties dispatched on `this`, without requiring
// reified static type information at the call site.

@_cdecl("__kk_kclass_simple_name")
public func __kk_kclass_simple_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    if let name = runtimeRangeClassQualifiedName(typeToken: box.typeToken),
       let simpleName = name.split(separator: ".").last {
        return runtimeMakeStringRaw(String(simpleName))
    }
    if let metadata = box.metadata {
        // KUU-3828: anonymous object literals have no simple name on the JVM
        // even though the compiler registers a synthetic internal name.
        return metadata.isAnonymous
            ? runtimeNullSentinelInt
            : runtimeMakeStringRaw(metadata.simpleName)
    }
    return __kk_type_token_simple_name(box.typeToken, box.nameHint)
}

@_cdecl("__kk_kclass_qualified_name")
public func __kk_kclass_qualified_name(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw) else {
        return runtimeNullSentinelInt
    }
    if let name = runtimeRangeClassQualifiedName(typeToken: box.typeToken) {
        return runtimeMakeStringRaw(name)
    }
    if let metadata = box.metadata {
        return metadata.isLocal
            ? runtimeNullSentinelInt
            : runtimeMakeStringRaw(runtimeKClassQualifiedName(metadata.qualifiedName))
    }
    return __kk_type_token_qualified_name(box.typeToken, box.nameHint)
}


/// Called during module initialization to populate the global metadata registry
/// from the binary metadata blob emitted by `RuntimeReflectionMetadataEmitter`.
///
/// Parameters are passed as intptr_t values:
/// - typeToken: The type token identifying the type.
/// - qualifiedNameRaw: Runtime string pointer for the qualified name.
/// - simpleNameRaw: Runtime string pointer for the simple name.
/// - supertypeNameRaw: Runtime string pointer for the supertype display names,
///   '|'-joined when there is more than one (0 if none).
/// - flags: Bit-packed flags (bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///          bit 3=interface, bit 4=object, bit 5=enumClass, bit 6=annotationClass,
///          bit 7=abstract).
/// - fieldCount: Number of declared fields (-1 if unknown).
/// - memberCount: Number of declared members (-1 if unknown).
@_cdecl("__kk_kclass_register_metadata")
public func __kk_kclass_register_metadata(
    _ typeToken: Int,
    _ qualifiedNameRaw: Int,
    _ simpleNameRaw: Int,
    _ supertypeNameRaw: Int,
    _ flags: Int,
    _ fieldCount: Int,
    _ memberCount: Int,
    _ constructorCount: Int
) -> Int {
    return __kk_kclass_register_metadata_v2(
        typeToken, qualifiedNameRaw, simpleNameRaw, supertypeNameRaw,
        flags, fieldCount, memberCount, constructorCount, 0, 0
    )
}

/// - visibilityRaw: Runtime string pointer for visibility ("PUBLIC", "INTERNAL", etc.), 0 if unknown.
/// - typeParameterCount: Number of type parameters on the class.
/// Flags bit layout: bit 0=dataClass, bit 1=sealedClass, bit 2=valueClass,
///   bit 3=interface, bit 4=object, bit 5=enumClass, bit 6=annotationClass,
///   bit 7=abstract, bit 8=final, bit 9=open,
///   bit 10=inner, bit 11=companion, bit 12=funInterface, bit 13=local,
///   bit 14=anonymous (object literal).
@_cdecl("__kk_kclass_register_metadata_v2")
public func __kk_kclass_register_metadata_v2(
    _ typeToken: Int,
    _ qualifiedNameRaw: Int,
    _ simpleNameRaw: Int,
    _ supertypeNameRaw: Int,
    _ flags: Int,
    _ fieldCount: Int,
    _ memberCount: Int,
    _ constructorCount: Int,
    _ visibilityRaw: Int,
    _ typeParameterCount: Int
) -> Int {
    let qualifiedName = extractString(from: UnsafeMutableRawPointer(bitPattern: qualifiedNameRaw)) ?? "Unknown"
    let simpleName = extractString(from: UnsafeMutableRawPointer(bitPattern: simpleNameRaw)) ?? "Unknown"
    // The compiler joins all direct supertype display names with '|'; Kotlin
    // qualified type names never contain that character.
    let supertypeDisplayNames: [String]
    if supertypeNameRaw != 0, supertypeNameRaw != runtimeNullSentinelInt,
       let joined = extractString(from: UnsafeMutableRawPointer(bitPattern: supertypeNameRaw)),
       !joined.isEmpty
    {
        supertypeDisplayNames = joined.split(separator: "|").map(String.init)
    } else {
        supertypeDisplayNames = []
    }

    let visibility: String
    if visibilityRaw != 0, visibilityRaw != runtimeNullSentinelInt,
       let visStr = extractString(from: UnsafeMutableRawPointer(bitPattern: visibilityRaw))
    {
        visibility = visStr
    } else {
        visibility = "PUBLIC"
    }

    let entry = RuntimeKClassMetadataEntry(
        qualifiedName: qualifiedName,
        simpleName: simpleName,
        supertypeDisplayNames: supertypeDisplayNames,
        isDataClass: (flags & (1 << 0)) != 0,
        isSealedClass: (flags & (1 << 1)) != 0,
        isValueClass: (flags & (1 << 2)) != 0,
        isInterface: (flags & (1 << 3)) != 0,
        isObject: (flags & (1 << 4)) != 0,
        isEnumClass: (flags & (1 << 5)) != 0,

        isAbstract: (flags & (1 << 7)) != 0,
        fieldCount: fieldCount,
        memberCount: memberCount,
        constructorCount: constructorCount,
        isFinal: (flags & (1 << 8)) != 0,
        isOpen: (flags & (1 << 9)) != 0,
        visibility: visibility,
        typeParameterCount: typeParameterCount,
        isInner: (flags & (1 << 10)) != 0,
        isCompanion: (flags & (1 << 11)) != 0,
        isFunInterface: (flags & (1 << 12)) != 0,
        isLocal: (flags & (1 << 13)) != 0,
        isAnonymous: (flags & (1 << 14)) != 0
    )
    runtimeKClassMetadataRegistry.register(typeToken: typeToken, entry: entry)
    return 0
}

/// Adds one declared type parameter to the metadata for a KClass.
@_cdecl("__kk_kclass_register_type_parameter")
public func __kk_kclass_register_type_parameter(
    _ typeToken: Int,
    _ index: Int,
    _ identity: Int,
    _ nameRaw: Int,
    _ varianceOrdinal: Int,
    _ isReified: Int,
    _ upperBoundsRaw: Int
) -> Int {
    guard let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) else {
        return 0
    }
    let parameterRaw = __kk_ktypeparameter_create(identity, nameRaw, varianceOrdinal, isReified)
    if runtimeReflectionObject(from: upperBoundsRaw, as: RuntimeListBox.self) != nil {
        _ = __kk_ktypeparameter_set_upper_bounds(parameterRaw, upperBoundsRaw)
    }
    runtimeKClassMetadataRegistry.registerTypeParameter(
        typeToken: typeToken,
        index: index,
        metadata: RuntimeKTypeParameterMetadata(
            identity: identity,
            name: name,
            varianceOrdinal: varianceOrdinal
        )
    )
    return 0
}

/// Stores the Java reflection owner and member for a local or nested class.
/// `memberKind` is 0 for no member, 1 for a method, and 2 for a constructor.
@_cdecl("__kk_kclass_register_enclosing_metadata")
public func __kk_kclass_register_enclosing_metadata(
    _ typeToken: Int,
    _ enclosingClassNameRaw: Int,
    _ declaringClassNameRaw: Int,
    _ memberKind: Int,
    _ memberNameRaw: Int,
    _ memberSignatureRaw: Int
) -> Int {
    let enclosingClassName = extractString(
        from: UnsafeMutableRawPointer(bitPattern: enclosingClassNameRaw)
    )
    let declaringClassName = extractString(
        from: UnsafeMutableRawPointer(bitPattern: declaringClassNameRaw)
    )
    let memberName = extractString(from: UnsafeMutableRawPointer(bitPattern: memberNameRaw))
    let memberSignature = extractString(from: UnsafeMutableRawPointer(bitPattern: memberSignatureRaw))
    let kind = RuntimeKClassEnclosingMember.Kind(rawValue: memberKind)
    let member: RuntimeKClassEnclosingMember?
    if let kind, let memberName, let memberSignature {
        member = RuntimeKClassEnclosingMember(
            kind: kind,
            name: memberName,
            signature: memberSignature
        )
    } else {
        member = nil
    }
    runtimeKClassMetadataRegistry.registerEnclosingMetadata(
        typeToken: typeToken,
        enclosingClassName: enclosingClassName,
        declaringClassName: declaringClassName,
        enclosingMember: member
    )
    return 0
}

/// Registers a compiler-derived JVM binary name without changing qualifiedName.
@_cdecl("__kk_kclass_register_display_name")
public func __kk_kclass_register_display_name(_ typeToken: Int, _ displayNameRaw: Int) -> Int {
    if let displayName = extractString(from: UnsafeMutableRawPointer(bitPattern: displayNameRaw)) {
        runtimeKClassMetadataRegistry.setDisplayName(typeToken: typeToken, displayName: displayName)
    }
    return 0
}

@_cdecl("__kk_kclass_register_cast_name")
public func __kk_kclass_register_cast_name(_ typeToken: Int, _ castNameRaw: Int) -> Int {
    if let castName = extractString(from: UnsafeMutableRawPointer(bitPattern: castNameRaw)) {
        runtimeKClassMetadataRegistry.setClassCastName(typeToken: typeToken, name: castName)
    }
    return 0
}

@_cdecl("__kk_kclass_is_data")
public func __kk_kclass_is_data(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isDataClass ? 1 : 0
}

@_cdecl("__kk_kclass_is_sealed")
public func __kk_kclass_is_sealed(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isSealedClass ? 1 : 0
}

@_cdecl("__kk_kclass_is_value")
public func __kk_kclass_is_value(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isValueClass ? 1 : 0
}

@_cdecl("__kk_kclass_is_interface")
public func __kk_kclass_is_interface(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isInterface ? 1 : 0
}

@_cdecl("__kk_kclass_is_object")
public func __kk_kclass_is_object(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isObject ? 1 : 0
}

@_cdecl("__kk_kclass_is_enum")
public func __kk_kclass_is_enum(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isEnumClass ? 1 : 0
}


@_cdecl("__kk_kclass_is_inner")
public func __kk_kclass_is_inner(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isInner ? 1 : 0
}

@_cdecl("__kk_kclass_is_companion")
public func __kk_kclass_is_companion(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isCompanion ? 1 : 0
}

@_cdecl("__kk_kclass_is_fun")
public func __kk_kclass_is_fun(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isFunInterface ? 1 : 0
}

@_cdecl("__kk_kclass_is_abstract")
public func __kk_kclass_is_abstract(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isAbstract ? 1 : 0
}


/// A class is final if it is not abstract, not open, and not an interface.
@_cdecl("__kk_kclass_is_final")
public func __kk_kclass_is_final(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isFinal ? 1 : 0
}

@_cdecl("__kk_kclass_is_open")
public func __kk_kclass_is_open(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return 0
    }
    return metadata.isOpen ? 1 : 0
}

/// Returns the visibility of this KClass as a `kotlin.reflect.KVisibility`
/// enum box (PUBLIC=0, PROTECTED=1, INTERNAL=2, PRIVATE=3 — the same ordinal
/// mapping `__kk_kcallable_get_metadata` uses for callable visibility).
/// Returns null sentinel if unknown.
@_cdecl("__kk_kclass_visibility")
public func __kk_kclass_visibility(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return runtimeNullSentinelInt
    }
    let names = ["PUBLIC", "PROTECTED", "INTERNAL", "PRIVATE"]
    let ordinal = names.firstIndex(of: metadata.visibility) ?? 0
    return kk_enum_box_ordinal(
        ordinal,
        runtimeMakeStringRaw(names[ordinal]),
        Int(runtimeStableNominalTypeID(fqName: "kotlin.reflect.KVisibility"))
    )
}

/// Returns the type parameters of this KClass as runtime KTypeParameter boxes.
/// Returns an empty list if no type parameters.
@_cdecl("__kk_kclass_type_parameters")
public func __kk_kclass_type_parameters(_ kclassRaw: Int) -> Int {
    guard let box = runtimeKClassBox(from: kclassRaw),
          let metadata = box.metadata else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
    let qualifiedName = metadata.qualifiedName
    let parameters = runtimeKClassTypeParameterHandles(
        qualifiedName: qualifiedName,
        metadata: metadata
    )
    return registerRuntimeObject(RuntimeListBox(elements: parameters))
}
