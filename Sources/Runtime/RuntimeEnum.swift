
struct RuntimeEnumValueDescriptor {
    let ordinal: Int
    let name: String
    let classID: Int64
}

// Runtime support for enum valueOf (STDLIB-173) and enum name/ordinal helpers.

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
/// backing array, tagging the box with the entry's declared name and the
/// enum class's stable nominal type ID.
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
    let name = extractString(from: UnsafeMutableRawPointer(bitPattern: namePtr))
    // Tagged-handle registration keeps the box's raw address out of
    // `objectPointers`, so a raw scalar that equals that address cannot be
    // mistaken for this box by the `kk_box_*` pass-through (KUU-857).
    return registerTaggedRuntimeObject(
        RuntimeIntBox(ordinal, enumEntryName: name, enumClassID: Int64(classID)),
        typeID: Int64(classID)
    )
}

/// Creates an `Array` of enum instances for `enumValues<T>()` and `T.values()`.
///
/// The lowering stage builds an array of enum singleton objects (`RuntimeArrayBox`) and
/// passes it to this runtime helper together with the declared size.
/// Returns `RuntimeArrayBox` to match Kotlin JVM's `Array<T>` return type.
@_cdecl("kk_enum_make_values_array")
public func kk_enum_make_values_array(_ valuesRaw: Int, _ count: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeArrayBox(length: 0))
    }

    let safeCount = max(0, min(count, values.count))
    let box = RuntimeArrayBox(length: safeCount)
    box.values = Array(values.values.prefix(safeCount))
    return registerRuntimeObject(box)
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

/// Returns a fresh Array<T> using the enum values registered for its reified
/// type token. Kotlin's enumValues<T>() returns a new array on each call.
@_cdecl("kk_enum_values_for_token")
public func kk_enum_values_for_token(_ typeToken: Int) -> Int {
    guard let values = runtimeStorage.withMetadataLock({ $0.enumValuesByTypeToken[Int64(typeToken)] }) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: enumValues received an unregistered enum type token \(typeToken)")
    }
    let handles = values.map { value in
        registerTaggedRuntimeObject(
            RuntimeIntBox(value.ordinal, enumEntryName: value.name, enumClassID: value.classID),
            typeID: value.classID
        )
    }
    let box = RuntimeArrayBox(length: handles.count)
    box.elements = handles
    return registerRuntimeObject(box)
}

/// Creates a `List` of enum instances for `T.entries`.
///
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

/// Creates a non-cached entries view over the supplied Array backing store.
@_cdecl("__kk_enum_entries_from_array")
public func kk_enum_entries_from_array(_ valuesRaw: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []), typeID: listRuntimeTypeID)
    }
    return registerRuntimeObject(RuntimeListBox(arrayViewOf: values), typeID: listRuntimeTypeID)
}
