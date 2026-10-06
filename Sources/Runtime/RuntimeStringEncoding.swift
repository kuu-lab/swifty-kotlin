// String ↔ ByteArray encoding/decoding and Charset constants.
// Split out from `RuntimeStringStdlib.swift`.

import Foundation
import RuntimeABI

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
    __kk_string_toByteArray_charset(runtimeMakeStringRaw(source), charsetTag)
}

private func runtimeSignedByteValue(_ value: Int) -> Int {
    Int(Int8(bitPattern: UInt8(truncatingIfNeeded: value)))
}

@_cdecl("__kk_string_toByteArray_flat")
public func __kk_string_toByteArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeMakeArrayRaw(KotlinStringSurrogateEncoding.unicodeString(source).utf8.map { Int(Int8(bitPattern: $0)) })
}
@_cdecl("__kk_charset_utf_8")
public func __kk_charset_utf_8() -> Int { CharsetTag.utf8.rawValue }

@_cdecl("__kk_charset_iso_8859_1")
public func __kk_charset_iso_8859_1() -> Int { CharsetTag.iso8859_1.rawValue }

@_cdecl("__kk_charset_us_ascii")
public func __kk_charset_us_ascii() -> Int { CharsetTag.usASCII.rawValue }

@_cdecl("__kk_charset_utf_16")
public func __kk_charset_utf_16() -> Int { CharsetTag.utf16.rawValue }

@_cdecl("__kk_charset_utf_16be")
public func __kk_charset_utf_16be() -> Int { CharsetTag.utf16be.rawValue }

@_cdecl("__kk_charset_utf_16le")
public func __kk_charset_utf_16le() -> Int { CharsetTag.utf16le.rawValue }

@_cdecl("__kk_charset_utf_32")
public func __kk_charset_utf_32() -> Int { CharsetTag.utf32.rawValue }

@_cdecl("__kk_charset_utf_32be")
public func __kk_charset_utf_32be() -> Int { CharsetTag.utf32be.rawValue }

@_cdecl("__kk_charset_utf_32le")
public func __kk_charset_utf_32le() -> Int { CharsetTag.utf32le.rawValue }

@_cdecl("__kk_charset_name")
public func __kk_charset_name(_ charsetTag: Int) -> Int {
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_charset_name unsupported charset ID \(charsetTag)")
    }
    let name: String
    switch tag {
    case .utf8: name = "UTF-8"
    case .iso8859_1: name = "ISO-8859-1"
    case .usASCII: name = "US-ASCII"
    case .utf16: name = "UTF-16"
    case .utf16be: name = "UTF-16BE"
    case .utf16le: name = "UTF-16LE"
    case .utf32: name = "UTF-32"
    case .utf32be: name = "UTF-32BE"
    case .utf32le: name = "UTF-32LE"
    }
    return runtimeMakeStringRaw(name)
}

// STDLIB-581: String.toByteArray(charset: Charset)
@_cdecl("__kk_string_toByteArray_charset")
public func __kk_string_toByteArray_charset(_ strRaw: Int, _ charsetTag: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        // Unknown charset — fall back to UTF-8. Sema types this as List<Int>.
        return runtimeMakeListRaw(KotlinStringSurrogateEncoding.unicodeString(source).utf8.map { runtimeSignedByteValue(Int($0)) })
    }
    let bytes: [Int]
    switch tag {
    case .utf8:
        bytes = KotlinStringSurrogateEncoding.unicodeString(source).utf8.map(Int.init)
    case .iso8859_1:
        // ISO-8859-1: each UTF-16 code unit <= 0xFF maps 1:1; others replaced with '?'
        // Using utf16 (not unicodeScalars) to match Kotlin/JVM semantics where
        // non-BMP characters produce two surrogate code units, each replaced.
        bytes = runtimeKotlinStringUTF16CodeUnits(source).map { unit in
            unit <= 0xFF ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .usASCII:
        // US-ASCII: each UTF-16 code unit <= 0x7F maps 1:1; others replaced with '?'
        bytes = runtimeKotlinStringUTF16CodeUnits(source).map { unit in
            unit <= 0x7F ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .utf16:
        // UTF-16 with BOM (big-endian BOM then big-endian data, matching Kotlin/JVM)
        var result: [Int] = [0xFE, 0xFF] // BOM
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16be:
        var result: [Int] = []
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16le:
        var result: [Int] = []
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit & 0xFF))
            result.append(Int(unit >> 8))
        }
        bytes = result
    case .utf32:
        // UTF-32 with BOM (big-endian)
        var result: [Int] = [0x00, 0x00, 0xFE, 0xFF] // BOM
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32be:
        var result: [Int] = []
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32le:
        var result: [Int] = []
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int(v & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 24) & 0xFF))
        }
        bytes = result
    }
    // Sema types toByteArray(charset) as List<Int> — return ListBox.
    return runtimeMakeListRaw(bytes.map { runtimeSignedByteValue($0) })
}

@_cdecl("__kk_string_toByteArray_charset_flat")
public func __kk_string_toByteArray_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetTag: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard let tag = CharsetTag(rawValue: charsetTag) else {
        return runtimeMakeArrayRaw(KotlinStringSurrogateEncoding.unicodeString(source).utf8.map { runtimeSignedByteValue(Int($0)) })
    }
    let bytes: [Int]
    switch tag {
    case .utf8:
        bytes = KotlinStringSurrogateEncoding.unicodeString(source).utf8.map(Int.init)
    case .iso8859_1:
        bytes = runtimeKotlinStringUTF16CodeUnits(source).map { unit in
            unit <= 0xFF ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .usASCII:
        bytes = runtimeKotlinStringUTF16CodeUnits(source).map { unit in
            unit <= 0x7F ? Int(unit) : Int(UInt8(ascii: "?"))
        }
    case .utf16:
        var result: [Int] = [0xFE, 0xFF]
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16be:
        var result: [Int] = []
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit >> 8))
            result.append(Int(unit & 0xFF))
        }
        bytes = result
    case .utf16le:
        var result: [Int] = []
        for unit in runtimeKotlinStringUTF16CodeUnits(source) {
            result.append(Int(unit & 0xFF))
            result.append(Int(unit >> 8))
        }
        bytes = result
    case .utf32:
        var result: [Int] = [0x00, 0x00, 0xFE, 0xFF]
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32be:
        var result: [Int] = []
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int((v >> 24) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int(v & 0xFF))
        }
        bytes = result
    case .utf32le:
        var result: [Int] = []
        for scalar in KotlinStringSurrogateEncoding.unicodeString(source).unicodeScalars {
            let v = scalar.value
            result.append(Int(v & 0xFF))
            result.append(Int((v >> 8) & 0xFF))
            result.append(Int((v >> 16) & 0xFF))
            result.append(Int((v >> 24) & 0xFF))
        }
        bytes = result
    }
    return runtimeMakeArrayRaw(bytes.map { runtimeSignedByteValue($0) })
}
@_cdecl("__kk_string_encodeToByteArray_flat")
public func __kk_string_encodeToByteArray_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeMakeArrayRaw(KotlinStringSurrogateEncoding.unicodeString(source).utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
// Slices by UTF-16 code unit range to match Kotlin String indexing semantics.
@_cdecl("__kk_string_encodeToByteArray_range_flat")
public func __kk_string_encodeToByteArray_range_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ startIndex: Int,
    _ endIndex: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let slice = runtimeUTF16Substring(source, startIndex: startIndex, endIndex: endIndex)
    return runtimeMakeArrayRaw(KotlinStringSurrogateEncoding.unicodeString(slice).utf8.map { Int(Int8(bitPattern: $0)) })
}

// STDLIB-573: String.encodeToByteArray(charset) — charset-aware overload.
// Sema types this as ByteArray — must return ArrayBox.
// __kk_string_toByteArray_charset returns ListBox (Sema: List<Int>), so we
// convert the elements here rather than delegating directly.
@_cdecl("__kk_string_encodeToByteArray_charset_flat")
public func __kk_string_encodeToByteArray_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetID: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let raw = runtimeMakeStringRaw(source)
    let listHandle = __kk_string_toByteArray_charset(raw, charsetID)
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
            return runtimeMakeStringRaw(KotlinStringSurrogateEncoding.encode(decoded))
        }
        outThrown?.pointee = runtimeAllocateMalformedInputException()
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(KotlinStringSurrogateEncoding.encode(String(decoding: bytes, as: UTF8.self)))
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
@_cdecl("__kk_bytearray_decodeToString")
public func __kk_bytearray_decodeToString(_ arrRaw: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_bytearray_decodeToString received invalid byte array handle \(arrRaw)")
    }
    // Use truncating conversion to match Kotlin's signed-byte semantics:
    // negative values (e.g. -1) become their unsigned equivalent (255).
    let bytes = elements.map { UInt8(truncatingIfNeeded: $0) }
    // Use String(decoding:as:) for UTF-8 replacement decoding: malformed
    // sequences produce U+FFFD instead of returning nil/empty.
    let decoded = String(decoding: bytes, as: UTF8.self)
    return runtimeMakeStringRaw(KotlinStringSurrogateEncoding.encode(decoded))
}

// STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex)
@_cdecl("__kk_bytearray_decodeToString_range")
public func __kk_bytearray_decodeToString_range(
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
@_cdecl("__kk_bytearray_decodeToString_range_throw")
public func __kk_bytearray_decodeToString_range_throw(
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
@_cdecl("__kk_byteArray_toKString")
public func __kk_byteArray_toKString(
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
// Charset IDs follow CharsetTag: UTF-8, Latin-1, ASCII, and endian-aware UTF-16/32.
@_cdecl("__kk_bytearray_decodeToString_charset")
public func __kk_bytearray_decodeToString_charset(_ arrRaw: Int, _ charsetId: Int) -> Int {
    guard let elements = runtimeByteArrayElements(from: arrRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_bytearray_decodeToString_charset received invalid byte array handle \(arrRaw)")
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
    case 3, 4, 5: // UTF-16, UTF-16BE, UTF-16LE
        var littleEndian = charsetId == 5
        var offset = 0
        if charsetId == 3, bytes.count >= 2 {
            if bytes[0] == 0xff, bytes[1] == 0xfe {
                littleEndian = true
                offset = 2
            } else if bytes[0] == 0xfe, bytes[1] == 0xff {
                offset = 2
            }
        }
        var units: [UInt16] = []
        func unit(at index: Int) -> UInt16 {
            let first = UInt16(bytes[index])
            let second = UInt16(bytes[index + 1])
            return littleEndian ? first | (second << 8) : (first << 8) | second
        }
        while offset + 1 < bytes.count {
            let first = unit(at: offset)
            offset += 2
            if (0xd800...0xdbff).contains(first) {
                // JVM UTF-16 decoders replace an invalid surrogate pair as one malformed unit.
                guard offset + 1 < bytes.count else {
                    units.append(0xfffd)
                    offset = bytes.count
                    break
                }
                let second = unit(at: offset)
                offset += 2
                if (0xdc00...0xdfff).contains(second) {
                    units.append(contentsOf: [first, second])
                } else {
                    units.append(0xfffd)
                }
            } else {
                units.append((0xdc00...0xdfff).contains(first) ? 0xfffd : first)
            }
        }
        if offset < bytes.count { units.append(0xfffd) }
        decoded = String(decoding: units, as: UTF16.self)
    case 6, 7, 8: // UTF-32, UTF-32BE, UTF-32LE
        var littleEndian = charsetId == 8
        var offset = 0
        if bytes.count >= 4 {
            if charsetId != 8, bytes[0...3].elementsEqual([0, 0, 0xfe, 0xff]) {
                offset = 4
            } else if charsetId != 7, bytes[0...3].elementsEqual([0xff, 0xfe, 0, 0]) {
                littleEndian = true
                offset = 4
            }
        }
        var units: [UInt32] = []
        while offset + 3 < bytes.count {
            let part = bytes[offset...offset + 3]
            let ordered = littleEndian ? Array(part.reversed()) : Array(part)
            units.append(ordered.reduce(0) { ($0 << 8) | UInt32($1) })
            offset += 4
        }
        if offset < bytes.count { units.append(0xfffd) }
        decoded = String(decoding: units, as: UTF32.self)
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_bytearray_decodeToString_charset unsupported charset ID \(charsetId)")
    }
    return runtimeMakeStringRaw(KotlinStringSurrogateEncoding.encode(decoded))
}
