import Foundation
import RuntimeABI

@_cdecl("kk_array_tag_type")
public func kk_array_tag_type(_ arrayRaw: Int, _ typeID: Int) -> Int {
    guard runtimeArrayBox(from: arrayRaw) != nil else {
        return arrayRaw
    }
    runtimeRegisterArrayType(rawValue: arrayRaw, typeID: Int64(typeID))
    return arrayRaw
}

@_cdecl("kk_array_new")
public func kk_array_new(_ length: Int) -> Int {
    let box = RuntimeArrayBox(length: length)
    let opaque = UnsafeMutableRawPointer(Unmanaged.passRetained(box).toOpaque())
    runtimeStorage.withGCLock { state in
        state.objectPointers.insert(UInt(bitPattern: opaque))
    }
    return Int(bitPattern: opaque)
}

/// Same as `kk_array_new`, but validates `length` first and throws
/// `NegativeArraySizeException` for negative sizes instead of silently
/// clamping to an empty array. Used by the `Array(size) { init }` family of
/// pseudo-constructors (Array, IntArray, ByteArray, ...), which must reject
/// negative sizes the way real Kotlin does.
@_cdecl("kk_array_new_checked")
public func kk_array_new_checked(_ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    guard length >= 0 else {
        runtimeSetThrown(outThrown, runtimeAllocateNegativeArraySizeException(message: "\(length)"))
        return 0
    }
    return kk_array_new(length)
}

@_cdecl("kk_array_get")
public func kk_array_get(_ arrayRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard index >= 0, index < array.count else {
        outThrown?.pointee = runtimeAllocateArrayIndexOutOfBoundsException(
            message: "Index \(index) out of bounds for length \(array.count)"
        )
        return 0
    }
    return array[index]
}

@_cdecl("kk_array_get_inbounds")
public func kk_array_get_inbounds(_ arrayRaw: Int, _ index: Int) -> Int {
    // Uses the O(1) subscript rather than `elements`, which copies the whole
    // backing store on every access. This is the hot path for object field
    // reads as well as array indexing.
    guard let array = runtimeArrayBox(from: arrayRaw),
          index >= 0, index < array.count
    else {
        runtimeStructuredPanic("kk_array_get_inbounds precondition failed")
    }
    return array[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let array = runtimeArrayBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "Array reference is null.")
        return 0
    }
    guard index >= 0, index < array.count else {
        outThrown?.pointee = runtimeAllocateArrayIndexOutOfBoundsException(
            message: "Index \(index) out of bounds for length \(array.count)"
        )
        return 0
    }
    array[index] = value
    return value
}

/// Stores an object field together with its static Any-fallback type tag.
/// Generated data-class constructors use this non-throwing entry point after
/// the normal inbounds layout checks have been performed by lowering.
@_cdecl("kk_array_set_typed")
public func kk_array_set_typed(
    _ arrayRaw: Int,
    _ index: Int,
    _ value: Int,
    _ anyFallbackTag: Int
) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          index >= 0,
          index < array.count
    else {
        return 0
    }
    array.setValue(
        value,
        at: index,
        anyFallbackTag: Int32(truncatingIfNeeded: anyFallbackTag)
    )
    return value
}

@_cdecl("kk_vararg_spread_concat")
public func kk_vararg_spread_concat(_ pairsArrayRaw: Int, _ pairCount: Int) -> Int {
    guard let pairs = runtimeArrayBox(from: pairsArrayRaw),
          pairCount > 0,
          pairs.count >= pairCount * 2 else { return kk_array_new(0) }
    var totalCount = 0
    for i in 0 ..< pairCount {
        let marker = pairs[i * 2]
        let value = pairs[i * 2 + 1]
        if marker == -1 {
            if let values = runtimeSpreadSourceValues(from: value) {
                totalCount += values.count
            }
        } else {
            totalCount += 1
        }
    }
    let result = kk_array_new(totalCount)
    if let box = runtimeArrayBox(from: result) {
        var writeIndex = 0
        for i in 0 ..< pairCount {
            let marker = pairs[i * 2]
            let sourceValue = pairs.values[i * 2 + 1]
            if marker == -1 {
                if let values = runtimeSpreadSourceValues(from: sourceValue.legacyRawValue) {
                    for element in values {
                        box.setValue(
                            element.legacyRawValue,
                            at: writeIndex,
                            anyFallbackTag: element.anyFallbackTag
                        )
                        writeIndex += 1
                    }
                }
            } else {
                box.setValue(
                    sourceValue.legacyRawValue,
                    at: writeIndex,
                    anyFallbackTag: sourceValue.anyFallbackTag
                )
                writeIndex += 1
            }
        }
    }
    return result
}
