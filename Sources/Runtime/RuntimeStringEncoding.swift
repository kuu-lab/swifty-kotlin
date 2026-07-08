// String ↔ ByteArray encoding/decoding and Charset constants.
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

enum CharsetTag: Int {
    case utf8 = 0
    case iso8859_1 = 1
    case usASCII = 2
    case utf16 = 3
    case utf16be = 4
    case utf16le = 5
    case utf32 = 6
    case utf32be = 7
    case utf32le = 8
}

func runtimeStringToByteArrayWithCharsetRaw(_ source: String, charsetTag: Int) -> Int {
    kk_string_toByteArray_charset(runtimeMakeStringRaw(source), charsetTag)
}

@_cdecl("kk_string_toByteArray")
public func kk_string_toByteArray(_ strRaw: Int) -> Int {
    // Sema types this as List<Int> — return ListBox so list-access codegen works.
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeListRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
}

@_cdecl("kk_string_toByteArray_flat")
public func kk_string_toByteArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeMakeArrayRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
}
@_cdecl("kk_charset_utf_8")
public func kk_charset_utf_8() -> Int { CharsetTag.utf8.rawValue }

@_cdecl("kk_charset_iso_8859_1")
public func kk_charset_iso_8859_1() -> Int { CharsetTag.iso8859_1.rawValue }

@_cdecl("kk_charset_us_ascii")
public func kk_charset_us_ascii() -> Int { CharsetTag.usASCII.rawValue }

@_cdecl("kk_charset_utf_16")
public func kk_charset_utf_16() -> Int { CharsetTag.utf16.rawValue }

@_cdecl("kk_charset_utf_16be")
public func kk_charset_utf_16be() -> Int { CharsetTag.utf16be.rawValue }

@_cdecl("kk_charset_utf_16le")
public func kk_charset_utf_16le() -> Int { CharsetTag.utf16le.rawValue }

@_cdecl("kk_charset_utf_32")
public func kk_charset_utf_32() -> Int { CharsetTag.utf32.rawValue }

@_cdecl("kk_charset_utf_32be")
public func kk_charset_utf_32be() -> Int { CharsetTag.utf32be.rawValue }

@_cdecl("kk_charset_utf_32le")
public func kk_charset_utf_32le() -> Int { CharsetTag.utf32le.rawValue }

// STDLIB-581: String.toByteArray(charset: Charset)
@_cdecl("kk_string_toByteArray_charset")
public func kk_string_toByteArray_charset(_ strRaw: Int, _ charsetTag: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        // Unknown charset — fall back to UTF-8. Sema types this as List<Int>.
        return runtimeMakeListRaw(source.utf8.map(Int.init))
    }
    let bytes: [Int]
    switch tag {
    case .utf8:
        bytes = source.utf8.map(Int.init)
    case .iso8859_1:
        // ISO-8859-1: each UTF-16 code unit <= 0xFF maps 1:1; others replaced with '?'
        // Using utf16 (not unicodeScalars) to match Kotlin/JVM semantics where
        // non-BMP characters produce two surrogate code units, each replaced.
        bytes = source.utf16.map { unit in
            unit <= 0xFF ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .usASCII:
        // US-ASCII: each UTF-16 code unit <= 0x7F maps 1:1; others replaced with '?'
        bytes = source.utf16.map { unit in
            unit <= 0x7F ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .utf16:
        // UTF-16 with BOM (big-endian BOM then big-endian data, matching Kotlin/JVM)
        var result: [Int] = [0xFE, 0xFF] // BOM
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16be:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16le:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit & 0xFF))
            result.append(Int(unit >> 8))
        }
        bytes = result
    case .utf32:
        // UTF-32 with BOM (big-endian)
        var result: [Int] = [0x00, 0x00, 0xFE, 0xFF] // BOM
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32be:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32le:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int(v & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 24) & 0xFF))
        }
        bytes = result
    }
    // Sema types toByteArray(charset) as List<Int> — return ListBox.
    return runtimeMakeListRaw(bytes)
}

@_cdecl("kk_string_toByteArray_charset_flat")
public func kk_string_toByteArray_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetTag: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        return runtimeMakeArrayRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
    }
    let bytes: [Int]
    switch tag {
    case .utf8:
        bytes = source.utf8.map(Int.init)
    case .iso8859_1:
        bytes = source.utf16.map { unit in
            unit <= 0xFF ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .usASCII:
        bytes = source.utf16.map { unit in
            unit <= 0x7F ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .utf16:
        var result: [Int] = [0xFE, 0xFF]
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16be:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16le:
        var result: [Int] = []
        for unit in source.utf16 {
            result.append(Int(unit & 0xFF))
            result.append(Int(unit >> 8))
        }
        bytes = result
    case .utf32:
        var result: [Int] = [0x00, 0x00, 0xFE, 0xFF]
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32be:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32le:
        var result: [Int] = []
        for scalar in source.unicodeScalars {
            let v = scalar.value
            result.append(Int(v & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 24) & 0xFF))
        }
        bytes = result
    }
    return runtimeMakeArrayRaw(bytes)
}
@_cdecl("kk_string_encodeToByteArray")
public func kk_string_encodeToByteArray(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeArrayRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
}

@_cdecl("kk_string_encodeToByteArray_flat")
public func kk_string_encodeToByteArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeMakeArrayRaw(source.utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
// Slices by UTF-16 code unit range to match Kotlin String indexing semantics.
@_cdecl("kk_string_encodeToByteArray_range")
public func kk_string_encodeToByteArray_range(_ strRaw: Int, _ startIndex: Int, _ endIndex: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let slice = runtimeUTF16Substring(source, startIndex: startIndex, endIndex: endIndex)
    return runtimeMakeArrayRaw(slice.utf8.map { Int(Int8(bitPattern: $0)) })
}

@_cdecl("kk_string_encodeToByteArray_range_flat")
public func kk_string_encodeToByteArray_range_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let slice = runtimeUTF16Substring(source, startIndex: startIndex, endIndex: endIndex)
    return runtimeMakeArrayRaw(slice.utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-573: String.encodeToByteArray(charset) — charset-aware overload.
// Sema types this as ByteArray — must return ArrayBox.
// kk_string_toByteArray_charset returns ListBox (Sema: List<Int>), so we
// convert the elements here rather than delegating directly.
@_cdecl("kk_string_encodeToByteArray_charset")
public func kk_string_encodeToByteArray_charset(_ strRaw: Int, _ charsetID: Int) -> Int {
    let listHandle = kk_string_toByteArray_charset(strRaw, charsetID)
    let elements = runtimeListBox(from: listHandle)?.elements ?? []
    return runtimeMakeArrayRaw(elements)
}

@_cdecl("kk_string_encodeToByteArray_charset_flat")
public func kk_string_encodeToByteArray_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetID: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let raw = runtimeMakeStringRaw(source)
    let listHandle = kk_string_toByteArray_charset(raw, charsetID)
    let elements = runtimeListBox(from: listHandle)?.elements ?? []
    return runtimeMakeArrayRaw(elements)
}

private func runtimeByteArrayElements(from raw: Int) -> [Int]? {
    if let list = runtimeListBox(from: raw) {
        return list.elements
    }
    if let array = runtimeArrayBox(from: raw) {
        return array.elements
    }
    return nil
}

private func runtimeByteArrayRangeError(
    startIndex: Int,
    endIndex: Int,
    size: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
        message: "startIndex=\(startIndex), endIndex=\(endIndex), size=\(size)"
    )
    return runtimeMakeStringRaw("")
}

private func runtimeDecodeUTF8Bytes(
    _ bytes: [UInt8],
    throwOnInvalidSequence: Bool,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    if throwOnInvalidSequence {
        if let decoded = String(data: Data(bytes), encoding: .utf8) {
            return runtimeMakeStringRaw(decoded)
        }
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "MalformedInputException: Input byte array has malformed UTF-8 sequence"
        )
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(String(decoding: bytes, as: UTF8.self))
}

private func runtimeDecodeByteArrayRange(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    throwOnInvalidSequence: Bool,
    outThrown: UnsafeMutablePointer<Int>?,
    caller: String
) -> Int {
    outThrown?.pointee = 0
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid byte array handle \(arrRaw)")
    }
    guard startIndex >= 0, endIndex >= startIndex, endIndex <= elements.count else {
        return runtimeByteArrayRangeError(
            startIndex: startIndex,
            endIndex: endIndex,
            size: elements.count,
            outThrown: outThrown
        )
    }
    let bytes = elements[startIndex..<endIndex].map { UInt8(truncatingIfNeeded: $0) }
    return runtimeDecodeUTF8Bytes(
        bytes,
        throwOnInvalidSequence: throwOnInvalidSequence,
        outThrown: outThrown
    )
}

// STDLIB-574: ByteArray.decodeToString()
@_cdecl("kk_bytearray_decodeToString")
public func kk_bytearray_decodeToString(_ arrRaw: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString received invalid byte array handle \(arrRaw)")
    }
    // Use truncating conversion to match Kotlin's signed-byte semantics:
    // negative values (e.g. -1) become their unsigned equivalent (255).
    let bytes = elements.map { UInt8(truncatingIfNeeded: $0) }
    // Use String(decoding:as:) for UTF-8 replacement decoding: malformed
    // sequences produce U+FFFD instead of returning nil/empty.
    let decoded = String(decoding: bytes, as: UTF8.self)
    return runtimeMakeStringRaw(decoded)
}

// STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex)
@_cdecl("kk_bytearray_decodeToString_range")
public func kk_bytearray_decodeToString_range(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeDecodeByteArrayRange(
        arrRaw,
        startIndex,
        endIndex,
        throwOnInvalidSequence: false,
        outThrown: outThrown,
        caller: #function
    )
}

// STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, throwOnInvalidSequence)
@_cdecl("kk_bytearray_decodeToString_range_throw")
public func kk_bytearray_decodeToString_range_throw(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ throwOnInvalidSequence: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeDecodeByteArrayRange(
        arrRaw,
        startIndex,
        endIndex,
        throwOnInvalidSequence: throwOnInvalidSequence != 0,
        outThrown: outThrown,
        caller: #function
    )
}

// STDLIB-CINTEROP-FN-029: kotlinx.cinterop.ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)
// Same UTF-8 decode semantics as decodeToString — toKString is cinterop's
// historical name for the identical operation.
@_cdecl("kk_byteArray_toKString")
public func kk_byteArray_toKString(
    _ arrRaw: Int,
    _ startIndex: Int,
    _ endIndex: Int,
    _ throwOnInvalidSequence: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeDecodeByteArrayRange(
        arrRaw,
        startIndex,
        endIndex,
        throwOnInvalidSequence: throwOnInvalidSequence != 0,
        outThrown: outThrown,
        caller: #function
    )
}

// STDLIB-574: ByteArray.decodeToString(charset)
// Charset IDs follow CharsetTag: 0 = UTF-8, 1 = ISO-8859-1 (Latin-1), 2 = US-ASCII
@_cdecl("kk_bytearray_decodeToString_charset")
public func kk_bytearray_decodeToString_charset(_ arrRaw: Int, _ charsetId: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString_charset received invalid byte array handle \(arrRaw)")
    }
    let bytes = elements.map { UInt8(truncatingIfNeeded: $0) }
    let decoded: String
    switch charsetId {
    case 0: // Charsets.UTF_8
        decoded = String(decoding: bytes, as: UTF8.self)
    case 1: // Charsets.ISO_8859_1 (Latin-1)
        // ISO-8859-1: each byte maps directly to its Unicode code point (0x00..0xFF)
        decoded = String(bytes.map { Character(Unicode.Scalar($0)) })
    case 2: // Charsets.US_ASCII
        // ASCII: bytes > 127 become replacement character U+FFFD
        decoded = String(bytes.map { $0 <= 127 ? Character(Unicode.Scalar($0)) : "\u{FFFD}" })
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_bytearray_decodeToString_charset unsupported charset ID \(charsetId)")
    }
    return runtimeMakeStringRaw(decoded)
}
