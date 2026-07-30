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

// KSP-406: replaceRange / removeRange are bundled Kotlin source
// (Stdlib/kotlin/text/StringSubstringSlice.kt); no runtime ABI remains.

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

// KSP-406: removeRange / replaceRange flat wrappers removed with the bundled
// Kotlin source migration (Stdlib/kotlin/text/StringSubstringSlice.kt).
