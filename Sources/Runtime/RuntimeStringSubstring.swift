// replaceFirst, replaceRange, and removeRange runtime primitives.
// Split out from `RuntimeStringStdlib.swift`.
//
// KSP-407: substringBefore/After/BeforeLast/AfterLast and replaceBefore/After/
// BeforeLast/AfterLast (String and Char delimiter variants) were migrated to
// bundled Kotlin source (`Stdlib/kotlin/text/StringSearchReplace.kt`), built
// purely on indexOf/lastIndexOf/substring. Their `kk_string_*`/`kk_string_*_flat`
// runtime primitives and private helpers were removed from this file.

import Foundation

// MARK: - STDLIB-188: replaceFirst / replaceRange

func runtimeStringReplaceFirst(_ strRaw: Int, _ oldRaw: Int, _ newRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let oldValue = runtimeStringFromRawOrPanic(oldRaw, caller: #function)
    let newValue = runtimeStringFromRawOrPanic(newRaw, caller: #function)
    guard let range = source.range(of: oldValue) else {
        return runtimeMakeStringRaw(source)
    }
    var result = source
    result.replaceSubrange(range, with: newValue)
    return runtimeMakeStringRaw(result)
}

@_cdecl("kk_string_replaceRange")
public func kk_string_replaceRange(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, runtimeAllocateStringIndexOutOfBoundsException(message: "Invalid range for replaceRange"))
        return 0
    }
    let first = range.first
    let last = range.last
    let length = scalars.count
    if first < 0 || first > length || last < -1 || last >= length || first > last + 1 {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "start=\(first), end=\(last + 1), length=\(length)")
        )
        return 0
    }
    let endIndex = last + 1
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let before = runtimeStringFromScalars(scalars[0 ..< first])
    let after = runtimeStringFromScalars(scalars[endIndex...])
    return runtimeMakeStringRaw(before + replacement + after)
}

// MARK: - STDLIB-TEXT-FN-062: replaceRange(startIndex, endIndex, replacement)

@_cdecl("kk_string_replaceRange_indices")
public func kk_string_replaceRange_indices(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ replacementRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let end = endRaw
    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "start=\(start), end=\(end), length=\(length)")
        )
        return 0
    }
    let replacement = runtimeStringFromRawOrPanic(replacementRaw, caller: #function)
    let before = runtimeStringFromScalars(scalars[0 ..< start])
    let after = runtimeStringFromScalars(scalars[end...])
    return runtimeMakeStringRaw(before + replacement + after)
}

// MARK: - STDLIB-TEXT-EDGE-008: removeRange

@_cdecl("kk_string_removeRange")
public func kk_string_removeRange(
    _ strRaw: Int,
    _ startRaw: Int,
    _ endRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let scalars = runtimeStringScalars(strRaw)
    let length = scalars.count
    let start = startRaw
    let end = endRaw
    if start < 0 || start > length || end < 0 || end > length || start > end {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateStringIndexOutOfBoundsException(message: "start=\(start), end=\(end), length=\(length)")
        )
        return 0
    }
    let before = runtimeStringFromScalars(scalars[0 ..< start])
    let after = runtimeStringFromScalars(scalars[end...])
    return runtimeMakeStringRaw(before + after)
}

@_cdecl("kk_string_removeRange_range")
public func kk_string_removeRange_range(
    _ strRaw: Int,
    _ rangeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let range = runtimeRangeBox(from: rangeRaw) else {
        runtimeSetThrown(outThrown, runtimeAllocateStringIndexOutOfBoundsException(message: "Invalid range for removeRange"))
        return 0
    }
    return kk_string_removeRange(strRaw, range.first, range.last + 1, outThrown)
}

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_replaceFirst_flat")
public func kk_string_replaceFirst_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ oldData: UnsafePointer<UInt8>?, _ oldLength: Int, _ oldByteCount: Int, _ oldHash: Int,
    _ newData: UnsafePointer<UInt8>?, _ newLength: Int, _ newByteCount: Int, _ newHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = runtimeStringReplaceFirst(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(oldData, oldLength, oldByteCount, oldHash),
        kk_string_from_flat(newData, newLength, newByteCount, newHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_removeRange_flat")
public func kk_string_removeRange_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ startRaw: Int, _ endRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removeRange(kk_string_from_flat(data, length, byteCount, hash), startRaw, endRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_removeRange_range_flat")
public func kk_string_removeRange_range_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ rangeRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_removeRange_range(kk_string_from_flat(data, length, byteCount, hash), rangeRaw, outThrown)
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceRange_flat")
public func kk_string_replaceRange_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ rangeRaw: Int,
    _ replacementData: UnsafePointer<UInt8>?, _ replacementLength: Int, _ replacementByteCount: Int, _ replacementHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceRange(
        kk_string_from_flat(data, length, byteCount, hash),
        rangeRaw,
        kk_string_from_flat(replacementData, replacementLength, replacementByteCount, replacementHash),
        outThrown
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}
