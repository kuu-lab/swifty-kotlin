import RuntimeABI

/// Kotlin IR string tables use WobblyTF8: UTF-8 extended to preserve an
/// isolated UTF-16 surrogate as a three-byte sequence. Swift's UTF-8 decoder
/// replaces those sequences, so decode to code units before forming text or
/// the runtime's lossless string-literal representation.
package enum KlibStringEncoding {
    package static func codeUnits(_ bytes: ArraySlice<UInt8>) throws -> [UInt16] {
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let first = bytes[index]
            index += 1
            if first < 0x80 {
                units.append(UInt16(first))
                continue
            }
            let count: Int
            var scalar: UInt32
            let minimum: UInt32
            switch first {
            case 0xC2 ... 0xDF: (count, scalar, minimum) = (1, UInt32(first & 0x1F), 0x80)
            case 0xE0 ... 0xEF: (count, scalar, minimum) = (2, UInt32(first & 0x0F), 0x800)
            case 0xF0 ... 0xF4: (count, scalar, minimum) = (3, UInt32(first & 0x07), 0x10000)
            default: throw KlibFormatError.corruptChunk("invalid WobblyTF8 leading byte")
            }
            guard count <= bytes.endIndex - index else {
                throw KlibFormatError.corruptChunk("truncated WobblyTF8 string")
            }
            for _ in 0 ..< count {
                let byte = bytes[index]
                index += 1
                guard byte & 0xC0 == 0x80 else {
                    throw KlibFormatError.corruptChunk("invalid WobblyTF8 continuation byte")
                }
                scalar = (scalar << 6) | UInt32(byte & 0x3F)
            }
            guard scalar >= minimum, scalar <= 0x10FFFF else {
                throw KlibFormatError.corruptChunk("invalid WobblyTF8 code point")
            }
            if scalar <= 0xFFFF {
                units.append(UInt16(scalar))
            } else {
                let offset = scalar - 0x10000
                units.append(UInt16(0xD800 + (offset >> 10)))
                units.append(UInt16(0xDC00 + (offset & 0x3FF)))
            }
        }
        return units
    }

    package static func text(_ bytes: ArraySlice<UInt8>) throws -> String {
        String(decoding: try codeUnits(bytes), as: UTF16.self)
    }

    package static func literal(_ bytes: ArraySlice<UInt8>) throws -> String {
        KotlinStringSurrogateEncoding.fromUTF16CodeUnits(try codeUnits(bytes))
    }
}
