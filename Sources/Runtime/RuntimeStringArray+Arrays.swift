import Foundation

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
    registerRuntimeObject(RuntimeArrayBox(length: length))
}

@_cdecl("kk_array_new_checked")
public func kk_array_new_checked(_ length: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard length >= 0 else {
            throw RuntimeThrownHandle(runtimeAllocateNegativeArraySizeException(message: "\(length)"))
        }
        return kk_array_new(length)
    }
}

@_cdecl("kk_array_get")
public func kk_array_get(_ arrayRaw: Int, _ index: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let array = runtimeArrayBox(from: arrayRaw) else {
            throw RuntimeThrownHandle(runtimeAllocateThrowable(message: "Array reference is null."))
        }
        guard index >= 0, index < array.count else {
            throw RuntimeThrownHandle(runtimeAllocateArrayIndexOutOfBoundsException(
                message: "Index \(index) out of bounds for length \(array.count)"
            ))
        }
        return array[index]
    }
}

@_cdecl("kk_array_get_inbounds")
public func kk_array_get_inbounds(_ arrayRaw: Int, _ index: Int) -> Int {
    guard let array = runtimeArrayBox(from: arrayRaw),
          index >= 0, index < array.count
    else {
        runtimeStructuredPanic("kk_array_get_inbounds precondition failed")
    }
    return array[index]
}

@_cdecl("kk_array_set")
public func kk_array_set(_ arrayRaw: Int, _ index: Int, _ value: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeThrowingBridge(outThrown) {
        guard let array = runtimeArrayBox(from: arrayRaw) else {
            throw RuntimeThrownHandle(runtimeAllocateThrowable(message: "Array reference is null."))
        }
        guard index >= 0, index < array.count else {
            throw RuntimeThrownHandle(runtimeAllocateArrayIndexOutOfBoundsException(
                message: "Index \(index) out of bounds for length \(array.count)"
            ))
        }
        // JVM arrays are reified: a store outside the allocation component throws
        // ArrayStoreException. Untagged arrays and the primitive-specialized
        // arrays carry no component metadata and keep the unchecked path; only
        // boxed values have a knowable runtime type (KUU-4439).
        if let component = array.componentType,
           let pointer = UnsafeMutableRawPointer(bitPattern: value),
           runtimeIsObjectPointer(pointer),
           !runtimeArrayElementIsAssignable(
               RuntimeValue(raw: value),
               sourceComponent: nil,
               to: component
           )
        {
            throw RuntimeThrownHandle(runtimeAllocateArrayStoreException(message: nil))
        }
        array[index] = value
        return value
    }
}

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
