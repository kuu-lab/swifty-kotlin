
struct RuntimeEnumValueDescriptor {
    let ordinal: Int
    let name: String
    let classID: Int64
}

/// Cache key for `GCState.enumIdentityBoxCache`: the enum class's stable
/// nominal type ID plus the entry ordinal uniquely identify a Kotlin enum
/// singleton.
struct RuntimeEnumBoxCacheKey: Hashable {
    let classID: Int64
    let ordinal: Int
}

/// Canonical Any-erased box for one enum entry. Kotlin/JVM enum entries are
/// singletons, so every boxing path — a direct `E.A` crossing an Any
/// boundary, a `values()`/`entries` element, a `valueOf` result — must hand
/// back one object for `===` to observe reference identity (KUU-2957).
///
/// The box keeps the tagged-handle representation `kk_enum_box_ordinal` has
/// always emitted, so its raw address stays out of `objectPointers` and a raw
/// scalar that equals that address cannot be mistaken for this box by the
/// `kk_box_*` pass-through (KUU-857). The shared handle is also registered in
/// `identityPrimitiveBoxHandles` so `kk_tag_value_class_box` clones it before
/// applying a value-class tag instead of mutating the canonical box.
func runtimeEnumIdentityBox(ordinal: Int, name: String?, classID: Int64) -> Int {
    let key = RuntimeEnumBoxCacheKey(classID: classID, ordinal: ordinal)
    let handle = runtimeStorage.withGCLock { state -> Int in
        if let cached = state.enumIdentityBoxCache[key] {
            return cached
        }
        let handle = registerTaggedPrimitiveBox(
            RuntimeIntBox(ordinal, enumEntryName: name, enumClassID: classID),
            inLockedState: &state
        )
        state.enumIdentityBoxCache[key] = handle
        state.identityPrimitiveBoxHandles.insert(UInt(bitPattern: handle))
        return handle
    }
    runtimeRegisterObjectType(rawValue: handle, classID: classID)
    return handle
}

/// Enum values are stored as ordinals, so their default object hash must mix
/// both the enum's nominal identity and the entry ordinal instead of exposing
/// the ordinal as the hash itself. The final adjustment avoids returning the
/// ordinal even in the unlikely event that the mixed value collides with it.
func runtimeEnumIdentityHashCode(_ ordinal: Int, _ classID: Int64) -> Int {
    guard ordinal != runtimeNullSentinelInt else { return 0 }

    var mixed = UInt64(bitPattern: classID)
        &+ (UInt64(bitPattern: Int64(ordinal)) &* 0x9E37_79B9_7F4A_7C15)
    mixed ^= mixed >> 30
    mixed &*= 0xBF58_476D_1CE4_E5B9
    mixed ^= mixed >> 27
    mixed &*= 0x94D0_49BB_1331_11EB
    mixed ^= mixed >> 31

    var hash = Int32(truncatingIfNeeded: mixed)
    if hash == Int32(truncatingIfNeeded: ordinal) {
        hash ^= Int32.min
    }
    return Int(hash)
}

/// Hashes an unboxed enum entry using the same identity key as Any-erased
/// enum boxes, whose runtime metadata carries the class ID.
@_cdecl("kk_enum_hash_code")
public func kk_enum_hash_code(_ ordinal: Int, _ classID: Int) -> Int {
    runtimeEnumIdentityHashCode(ordinal, Int64(classID))
}

/// Kotlin's `Enum.compareTo` returns the difference between enum ordinals.
@_cdecl("kk_enum_compareTo")
public func kk_enum_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    kk_unbox_int(lhsRaw) - kk_unbox_int(rhsRaw)
}

/// Reads the declared entry name after the concrete enum type is erased.
/// Erased toString rendering is registered independently, so this metadata
/// remains the declaration name even when the enum overrides toString.
@_cdecl("__kk_enum_name")
public func kk_enum_name(_ valueRaw: Int) -> Int {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: valueRaw),
          let box = tryCast(pointer, to: RuntimeIntBox.self),
          let name = box.enumEntryName
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: Enum.name received an invalid enum entry")
    }
    return runtimeMakeStringRaw(name)
}

@_cdecl("kk_enum_valueOf_throw")
public func kk_enum_valueOf_throw(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: nameRaw)) ?? "null"
    outThrown?.pointee = runtimeAllocateIllegalArgumentException(
        message: "No enum constant \(name)"
    )
    return 0
}

/// Boxes an enum ordinal for storage in an Any-erased `values()`/`entries`
/// backing array.
///
/// Every other enum value (a direct reference like `Direction.NORTH`, or a
/// `valueOf`/`$enumOrdinalToName` argument) is a raw ordinal Int. An element
/// read back out of `values()`/`entries` must round-trip through the same
/// `kk_unbox_int` that recovers those raw ordinals, so this produces a
/// genuine `RuntimeIntBox` rather than a distinct representation. The name
/// tag affects how generic Any-printing paths render the box once the
/// static enum type has been erased (see RuntimeIntBox.enumEntryName); the
/// class ID lets `is`/`as`/`as?`/`KClass.isInstance` recognize the boxed
/// value as an instance of its enum class (BUG-182).
@_cdecl("kk_enum_box_ordinal")
public func kk_enum_box_ordinal(_ ordinal: Int, _ namePtr: Int, _ classID: Int) -> Int {
    runtimeStorage.withMetadataLock { state in
        _ = state.enumClassifierIDs.insert(Int64(classID) & RuntimeTypeTokenEncoding.payloadMask)
    }
    // A nullable enum slot stores the null sentinel as its ordinal. Keep it
    // null: boxing it would produce a live non-null object for a Kotlin null
    // (KUU-2957). No valid ordinal is Int64.min, so genuine entries never
    // reach this branch.
    if ordinal == runtimeNullSentinelInt {
        return ordinal
    }
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: namePtr))
    return runtimeEnumIdentityBox(ordinal: ordinal, name: name, classID: Int64(classID))
}

/// Nominal type ID of `kotlin.Array`, tagged onto every array the enum
/// `values()`/`enumValues<T>()` helpers hand to Kotlin code. Ordinary array
/// creation sites emit `kk_array_tag_type` themselves; these intrinsics
/// allocate inside the runtime, so they must register the same tag or
/// `values() as Array<...>` / `values().sort()` (which casts to
/// `Array<Any?>` internally) sees an untyped object and throws
/// ClassCastException (KUU-3548).
private let runtimeEnumArrayNominalTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.Array")

/// Tags a runtime-allocated enum values array as `kotlin.Array` and installs
/// the reified component descriptor derived from the enum class's stable
/// nominal type ID, matching the metadata `arrayOf(...)` arrays receive from
/// `kk_array_tag_type` + `__kk_array_tag_component` at their creation sites.
/// `classifier` is the encoded type token for the enum class
/// (`nominalBase | classID << payloadShift`); `0` leaves the component
/// untagged.
private func runtimeRegisterEnumValuesArray(_ box: RuntimeArrayBox, classifier: Int) -> Int {
    let raw = registerRuntimeObject(box)
    runtimeRegisterArrayType(rawValue: raw, typeID: runtimeEnumArrayNominalTypeID)
    if classifier != 0 {
        let component = __kk_array_component_type(classifier, 0)
        if component != 0 {
            box.installComponentTypeIfAbsent(component)
        }
    }
    return raw
}

/// The lowering stage builds an array of enum singleton objects (`RuntimeArrayBox`) and
/// passes it to this runtime helper together with the declared size and the
/// enum class's stable nominal type ID.
/// Returns `RuntimeArrayBox` to match Kotlin JVM's `Array<T>` return type.
@_cdecl("kk_enum_make_values_array")
public func kk_enum_make_values_array(_ valuesRaw: Int, _ count: Int, _ classID: Int) -> Int {
    let classifier = classID != 0 ? runtimeNominalTypeToken(Int64(classID)) : 0
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return runtimeRegisterEnumValuesArray(RuntimeArrayBox(length: 0), classifier: classifier)
    }

    let safeCount = max(0, min(count, values.count))
    let box = RuntimeArrayBox(length: safeCount)
    box.values = Array(values.values.prefix(safeCount))
    return runtimeRegisterEnumValuesArray(box, classifier: classifier)
}

/// Registers boxed enum values for a reified `enumValues<T>()` call whose T is
/// only available as a runtime token inside a non-inline function.
@_cdecl("kk_enum_register_values")
public func kk_enum_register_values(_ typeToken: Int, _ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_enum_register_values received an invalid array")
    }
    let safeCount = max(0, min(count, values.count))
    let descriptors = values.values.prefix(safeCount).map { value -> RuntimeEnumValueDescriptor in
        guard let pointer = UnsafeMutableRawPointer(bitPattern: value.legacyRawValue),
              let box = tryCast(pointer, to: RuntimeIntBox.self),
              let name = box.enumEntryName,
              let classID = box.enumClassID
        else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_enum_register_values received an invalid enum entry")
        }
        return RuntimeEnumValueDescriptor(ordinal: box.value, name: name, classID: classID)
    }
    runtimeStorage.withMetadataLock { state in
        state.enumValuesByTypeToken[Int64(typeToken)] = descriptors
    }
    return 0
}

/// Kotlin's enumValues<T>() returns a new array on each call.
@_cdecl("kk_enum_values_for_token")
public func kk_enum_values_for_token(_ typeToken: Int) -> Int {
    guard let values = runtimeStorage.withMetadataLock({ $0.enumValuesByTypeToken[Int64(typeToken)] }) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: enumValues received an unregistered enum type token \(typeToken)")
    }
    // Elements go through the same canonical cache as kk_enum_box_ordinal so
    // `enumValues<E>()[0] === E.A` observes JVM singleton identity.
    let handles = values.map { value in
        runtimeEnumIdentityBox(ordinal: value.ordinal, name: value.name, classID: value.classID)
    }
    let box = RuntimeArrayBox(length: handles.count)
    box.elements = handles
    // `typeToken` is the encoded token kk_enum_register_values keyed this
    // enum under; it doubles as the component classifier for `as Array<E>`.
    return runtimeRegisterEnumValuesArray(box, classifier: typeToken)
}

/// `entries` returns `EnumEntries<T>` in Kotlin, which extends `List<E>`.
/// Returns `RuntimeListBox` to match the List-based API.
@_cdecl("kk_enum_make_entries_list")
public func kk_enum_make_entries_list(_ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let safeCount = max(0, min(count, values.count))
    return registerRuntimeObject(RuntimeListBox(elements: Array(values.elements.prefix(safeCount))))
}

/// Creates the per-enum cached `EnumEntries` list used by both `T.entries` and
/// the reified `enumEntries<T>()` intrinsic. The generated array is retained as
/// the list's backing view, so the source-backed Array overload remains
/// no-copy while the reified API preserves stable identity.
@_cdecl("kk_enum_make_entries_list_cached")
public func kk_enum_make_entries_list_cached(_ valuesRaw: Int, _ count: Int, _ classID: Int) -> Int {
    guard classID != 0 else {
        return kk_enum_make_entries_list(valuesRaw, count)
    }
    if let cached = runtimeStorage.withMetadataLock({ state in state.enumEntriesCache[Int64(classID)] }) {
        return cached
    }

    let list: RuntimeListBox
    if let values = runtimeArrayBox(from: valuesRaw) {
        let safeCount = max(0, min(count, values.count))
        if safeCount == values.count {
            list = RuntimeListBox(arrayViewOf: values)
        } else {
            let boundedValues = RuntimeArrayBox(length: safeCount)
            boundedValues.values = Array(values.values.prefix(safeCount))
            list = RuntimeListBox(arrayViewOf: boundedValues)
        }
    } else {
        list = RuntimeListBox(elements: [])
    }
    let raw = registerRuntimeObject(list, typeID: listRuntimeTypeID)
    return runtimeStorage.withMetadataLock { state in
        if let cached = state.enumEntriesCache[Int64(classID)] {
            return cached
        }
        state.enumEntriesCache[Int64(classID)] = raw
        return raw
    }
}

@_cdecl("__kk_enum_entries_from_array")
public func kk_enum_entries_from_array(_ valuesRaw: Int) -> Int {
    runtimeRegisterViewOrEmpty(
        from: valuesRaw,
        resolve: runtimeArrayBox,
        makeEmpty: { RuntimeListBox(elements: []) },
        makeView: { RuntimeListBox(arrayViewOf: $0) },
        typeID: listRuntimeTypeID
    )
}
