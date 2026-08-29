
// Runtime support for enum valueOf (STDLIB-173) and enum name/ordinal helpers.

import Foundation

private final class RuntimeEnumEntriesCache: @unchecked Sendable {
    private let lock = NSLock()
    private var entriesByEnumType: [Int64: Int] = [:]

    func value(for enumTypeID: Int64, elements: [Int]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entriesByEnumType[enumTypeID] {
            return cached
        }
        let raw = registerRuntimeObject(RuntimeListBox(elements: elements))
        entriesByEnumType[enumTypeID] = raw
        return raw
    }
}

private let runtimeEnumEntriesCache = RuntimeEnumEntriesCache()

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
    return registerRuntimeObject(RuntimeIntBox(ordinal, enumEntryName: name), typeID: Int64(classID))
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

    let safeCount = max(0, min(count, values.elements.count))
    let box = RuntimeArrayBox(length: safeCount)
    for i in 0..<safeCount {
        box.elements[i] = values.elements[i]
    }
    return registerRuntimeObject(box)
}

/// Creates a `List` of enum instances for `T.entries`.
///
/// `entries` returns `EnumEntries<T>` in Kotlin, which extends `List<E>`.
/// Returns `RuntimeListBox` to match the List-based API.
@_cdecl("kk_enum_make_entries_list")
public func kk_enum_make_entries_list(_ valuesRaw: Int, _ count: Int, _ classID: Int) -> Int {
    guard let values = runtimeArrayBox(from: valuesRaw) else {
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }

    let safeCount = max(0, min(count, values.elements.count))
    let elements = Array(values.elements.prefix(safeCount))
    // Kotlin's EnumEntries is a stable immutable collection for each enum
    // class. The compiler passes the enum class ID so empty enums retain the
    // same per-enum identity as non-empty enums.
    let cacheKey = classID != 0
        ? Int64(classID)
        : (safeCount > 0 ? runtimeObjectTypeID(rawValue: elements[0]) : nil)
    guard let cacheKey else {
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    }
    return runtimeEnumEntriesCache.value(for: cacheKey, elements: elements)
}
