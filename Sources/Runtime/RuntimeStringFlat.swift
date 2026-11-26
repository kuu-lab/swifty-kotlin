import Foundation
import RuntimeABI

func runtimeRegisterFlatStringResult(
    _ raw: Int,
    outLength: UnsafeMutablePointer<Int>?,
    outByteCount: UnsafeMutablePointer<Int>?,
    outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    if let data = kk_string_to_flat(raw, outLength, outByteCount, outHash) {
        return data
    }
    return runtimeRegisterFlatString(
        "",
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

func runtimeFlatStringCodeUnit(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int,
    index: Int
) -> (unit: UInt16?, utf16Length: Int) {
    if let units = runtimeFlatStringRegisteredUTF16CodeUnits(data: data) {
        if index >= 0, index < units.count {
            return (units[index], units.count)
        }
        return (nil, units.count)
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    if let unit = runtimeKotlinStringUTF16CodeUnit(source, at: index) {
        return (unit, -1)
    }
    return (nil, runtimeKotlinStringUTF16Length(source))
}

func runtimeFlatStringBoundaryCodeUnits(
    data: UnsafePointer<UInt8>?,
    length: Int,
    byteCount: Int,
    hash: Int
) -> (first: UInt16?, last: UInt16?, hasMultipleUnits: Bool) {
    if let units = runtimeFlatStringRegisteredUTF16CodeUnits(data: data) {
        return (units.first, units.last, units.count > 1)
    }
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    var iterator = KotlinStringSurrogateEncoding.UTF16CodeUnits(source).makeIterator()
    let first = iterator.next()
    var last = first
    var hasMultipleUnits = false
    while let unit = iterator.next() {
        last = unit
        hasMultipleUnits = true
    }
    return (first, last, hasMultipleUnits)
}

@_cdecl("kk_string_lowercase_flat")
public func kk_string_lowercase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_lowercase(kk_string_from_flat(data, length, byteCount, hash)),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("kk_string_uppercase_flat")
public func kk_string_uppercase_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        kk_string_uppercase(kk_string_from_flat(data, length, byteCount, hash)),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("__kk_string_first_flat")
public func __kk_string_first_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
        guard let first = boundary.first else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        }
        return Int(first)
    }
}

@_cdecl("__kk_string_last_flat")
public func __kk_string_last_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
        guard let last = boundary.last else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        }
        return Int(last)
    }
}

@_cdecl("__kk_string_single_flat")
public func __kk_string_single_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeThrowingBridge(outThrown) {
        let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
        guard let unit = boundary.first else {
            throw RuntimeThrownHandle(runtimeAllocateNoSuchElementException(message: "Char sequence is empty."))
        }
        guard !boundary.hasMultipleUnits else {
            throw RuntimeThrownHandle(runtimeAllocateIllegalArgumentException(message: "Char sequence has more than one element."))
        }
        return Int(unit)
    }
}

@_cdecl("__kk_string_firstOrNull_flat")
public func __kk_string_firstOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let first = boundary.first else { return runtimeNullSentinelInt }
    return Int(first)
}

@_cdecl("__kk_string_lastOrNull_flat")
public func __kk_string_lastOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let last = boundary.last else { return runtimeNullSentinelInt }
    return Int(last)
}

@_cdecl("__kk_string_singleOrNull_flat")
public func __kk_string_singleOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let boundary = runtimeFlatStringBoundaryCodeUnits(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let unit = boundary.first, !boundary.hasMultipleUnits else { return runtimeNullSentinelInt }
    return Int(unit)
}

@_cdecl("__kk_string_toInt_flat")
public func __kk_string_toInt_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toInt(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toInt_radix_flat")
public func __kk_string_toInt_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toInt_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toIntOrNull_flat")
public func __kk_string_toIntOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toIntOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toIntOrNull_radix_flat")
public func __kk_string_toIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toLong_flat")
public func __kk_string_toLong_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toLong(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toLongOrNull_flat")
public func __kk_string_toLongOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toLongOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toShort_flat")
public func __kk_string_toShort_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toShort(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toShortOrNull_flat")
public func __kk_string_toShortOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toShortOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toByte_flat")
public func __kk_string_toByte_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toByte(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toByte_radix_flat")
public func __kk_string_toByte_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toByte_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toByteOrNull_flat")
public func __kk_string_toByteOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toByteOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

@_cdecl("__kk_string_toFloat_flat")
public func __kk_string_toFloat_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toFloat(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toFloatOrNull_flat")
public func __kk_string_toFloatOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toFloatOrNull(kk_string_from_flat(data, length, byteCount, hash))
}
@_cdecl("__kk_string_toUByteOrNull_radix_flat")
public func __kk_string_toUByteOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUByteOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toUShortOrNull_radix_flat")
public func __kk_string_toUShortOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUShortOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("__kk_string_toUIntOrNull_radix_flat")
public func __kk_string_toUIntOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toUIntOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

@_cdecl("kk_string_replace_flat")
public func kk_string_replace_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ oldData: UnsafePointer<UInt8>?,
    _ oldLength: Int,
    _ oldByteCount: Int,
    _ oldHash: Int,
    _ newData: UnsafePointer<UInt8>?,
    _ newLength: Int,
    _ newByteCount: Int,
    _ newHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    runtimeRegisterFlatStringResult(
        runtimeStringReplace(
            kk_string_from_flat(data, length, byteCount, hash),
            kk_string_from_flat(oldData, oldLength, oldByteCount, oldHash),
            kk_string_from_flat(newData, newLength, newByteCount, newHash)
        ),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}
