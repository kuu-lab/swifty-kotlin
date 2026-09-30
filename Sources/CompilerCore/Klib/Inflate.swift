import Foundation

/// Errors raised while reading a .klib container: zip archive structure,
/// inflate, manifest layout, or entry access.
package enum KlibFormatError: Error, Equatable {
    case notAZipArchive
    case unsupportedCompressionMethod(UInt16)
    case unsupportedZip64
    case unsupportedMultiDisk
    case truncatedArchive
    case corruptLocalHeader(String)
    case entryNotFound(String)
    case corruptDeflateStream(String)
    case crcMismatch(String)
    case sizeMismatch(String)
    case missingManifest
    case missingManifestKey(String)
    case invalidKlibLayout(String)
    case unsafeEntryPath(String)
    case unreadableContainer(String)
    case corruptChunk(String)
    case corruptProto(String)
}

extension KlibFormatError: CustomStringConvertible {
    package var description: String {
        switch self {
        case .notAZipArchive: return "not a zip archive"
        case .unsupportedCompressionMethod(let m): return "unsupported compression method \(m)"
        case .unsupportedZip64: return "ZIP64 archives are not supported"
        case .unsupportedMultiDisk: return "multi-disk archives are not supported"
        case .truncatedArchive: return "truncated archive"
        case .corruptLocalHeader(let n): return "corrupt local header for '\(n)'"
        case .entryNotFound(let n): return "entry '\(n)' not found"
        case .corruptDeflateStream(let m): return "corrupt deflate stream: \(m)"
        case .crcMismatch(let n): return "CRC mismatch for '\(n)'"
        case .sizeMismatch(let m): return "size mismatch: \(m)"
        case .missingManifest: return "component has no manifest"
        case .missingManifestKey(let k): return "manifest is missing required key '\(k)'"
        case .invalidKlibLayout(let m): return "invalid klib layout: \(m)"
        case .unsafeEntryPath(let p): return "unsafe entry path '\(p)'"
        case .unreadableContainer(let p): return "unreadable container '\(p)'"
        case .corruptChunk(let m): return "corrupt IR chunk: \(m)"
        case .corruptProto(let m): return "corrupt protobuf stream: \(m)"
        }
    }
}

/// Pure-Swift DEFLATE decoder (RFC 1951 raw stream, as stored in zip method-8
/// entries and inside zlib/gzip wrappers). No external dependencies — the
/// compiler must run anywhere SwiftPM runs, including Linux CI without
/// libz assumptions.
package enum Inflater {
    package static func inflate(_ bytes: ArraySlice<UInt8>, uncompressedSize: Int? = nil) throws -> [UInt8] {
        var reader = BitReader(bytes: bytes)
        var output: [UInt8] = []
        output.reserveCapacity(uncompressedSize ?? bytes.count * 4)

        while true {
            let isFinal = try reader.bits(1) != 0
            let type = try reader.bits(2)
            switch type {
            case 0:
                try inflateStored(reader: &reader, into: &output)
            case 1:
                try inflateHuffman(reader: &reader, into: &output,
                                   literalTable: fixedLiteralTable,
                                   distanceTable: fixedDistanceTable)
            case 2:
                let tables = try readDynamicTables(reader: &reader)
                try inflateHuffman(reader: &reader, into: &output,
                                   literalTable: tables.literal,
                                   distanceTable: tables.distance)
            default:
                throw KlibFormatError.corruptDeflateStream("reserved block type")
            }
            if isFinal { break }
        }
        if let expected = uncompressedSize, output.count != expected {
            throw KlibFormatError.sizeMismatch(
                "deflate produced \(output.count) bytes, expected \(expected)"
            )
        }
        return output
    }

    // MARK: - Bit reader (LSB-first within each byte)

    private struct BitReader {
        let bytes: ArraySlice<UInt8>
        var index: ArraySlice<UInt8>.Index
        var bitBuffer: UInt64 = 0
        var bitCount = 0

        init(bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            self.index = bytes.startIndex
        }

        var isByteAligned: Bool { bitCount % 8 == 0 }

        mutating func alignToByte() {
            let drop = bitCount % 8
            bitBuffer >>= drop
            bitCount -= drop
        }

        mutating func bits(_ count: Int) throws -> Int {
            precondition(count <= 32)
            while bitCount < count {
                guard index < bytes.endIndex else {
                    throw KlibFormatError.corruptDeflateStream("unexpected end of input")
                }
                bitBuffer |= UInt64(bytes[index]) << bitCount
                index = bytes.index(after: index)
                bitCount += 8
            }
            let value = Int(bitBuffer & ((1 << UInt64(count)) - 1))
            bitBuffer >>= count
            bitCount -= count
            return value
        }

        mutating func alignedByte() throws -> UInt8 {
            precondition(isByteAligned)
            if bitCount > 0 {
                let value = UInt8(bitBuffer & 0xFF)
                bitBuffer >>= 8
                bitCount -= 8
                return value
            }
            guard index < bytes.endIndex else {
                throw KlibFormatError.corruptDeflateStream("unexpected end of input in stored block")
            }
            let value = bytes[index]
            index = bytes.index(after: index)
            return value
        }
    }

    // MARK: - Stored block (btype 0)

    private static func inflateStored(reader: inout BitReader, into output: inout [UInt8]) throws {
        reader.alignToByte()
        let lenLo = Int(try reader.alignedByte())
        let lenHi = Int(try reader.alignedByte())
        let nlenLo = Int(try reader.alignedByte())
        let nlenHi = Int(try reader.alignedByte())
        let len = lenLo | (lenHi << 8)
        let nlen = nlenLo | (nlenHi << 8)
        guard len == ~nlen & 0xFFFF else {
            throw KlibFormatError.corruptDeflateStream("stored block LEN/NLEN mismatch")
        }
        for _ in 0 ..< len {
            output.append(try reader.alignedByte())
        }
    }

    // MARK: - Huffman tables

    /// Canonical-Huffman decoding table: counts per code length plus the
    /// symbols sorted by (code length, symbol order). Decoding walks lengths
    /// 1...maxLen accumulating one bit at a time — same scheme as zlib's
    /// simplest decoder, O(maxLen) per symbol.
    private struct HuffmanTable {
        /// count[length] for length in 0...maxLength
        let counts: [Int]
        /// symbols sorted by code order
        let symbols: [Int]
        let maxLength: Int

        init(codeLengths: [Int]) throws {
            var counts = [Int](repeating: 0, count: 16)
            var maxLength = 0
            for length in codeLengths {
                guard length >= 0 && length <= 15 else {
                    throw KlibFormatError.corruptDeflateStream("invalid code length \(length)")
                }
                counts[length] += 1
                maxLength = max(maxLength, length)
            }
            self.counts = counts
            self.maxLength = maxLength
            var symbols = [Int](repeating: 0, count: codeLengths.count)
            // offsets[len] = first index into symbols for codes of this length.
            // Length-0 (unused) symbols are not stored, so counts[0] must not
            // contribute to the offsets — the accumulation starts at length 2
            // (offsets[1] stays 0).
            var offsets = [Int](repeating: 0, count: 16)
            for length in 2 ..< 16 {
                offsets[length] = offsets[length - 1] + counts[length - 1]
            }
            for (symbol, length) in codeLengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
            self.symbols = symbols
        }

        func decode(reader: inout BitReader) throws -> Int {
            // An all-zero-length table is legal in DEFLATE (a block that never
            // uses back-references may carry an empty distance table); it must
            // error here rather than form an invalid `1 ... 0` range.
            guard maxLength > 0 else {
                throw KlibFormatError.corruptDeflateStream("empty Huffman table")
            }
            var code = 0
            var first = 0
            var index = 0
            for length in 1 ... maxLength {
                code |= try reader.bits(1)
                let count = counts[length]
                if code >= first && code - first < count {
                    return symbols[index + code - first]
                }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw KlibFormatError.corruptDeflateStream("no matching Huffman code")
        }
    }

    /// The fixed literal/length code from RFC 1951 §3.2.6.
    private static let fixedLiteralTable: HuffmanTable = {
        var lengths = [Int](repeating: 0, count: 288)
        for i in 0 ... 143 { lengths[i] = 8 }
        for i in 144 ... 255 { lengths[i] = 9 }
        for i in 256 ... 279 { lengths[i] = 7 }
        for i in 280 ... 287 { lengths[i] = 8 }
        return try! HuffmanTable(codeLengths: lengths)
    }()

    private static let fixedDistanceTable: HuffmanTable = {
        let lengths = [Int](repeating: 5, count: 30)
        return try! HuffmanTable(codeLengths: lengths)
    }()

    /// Dynamic block header: literal/length, distance and code-length tables.
    private static func readDynamicTables(
        reader: inout BitReader
    ) throws -> (literal: HuffmanTable, distance: HuffmanTable) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else {
            throw KlibFormatError.corruptDeflateStream("too many Huffman codes")
        }

        // Order in which code-length code lengths are stored (RFC 1951 §3.2.7).
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0 ..< codeLengthCount {
            codeLengthLengths[order[i]] = try reader.bits(3)
        }
        let codeLengthTable = try HuffmanTable(codeLengths: codeLengthLengths)

        var lengths = [Int](repeating: 0, count: literalCount + distanceCount)
        var i = 0
        while i < lengths.count {
            let symbol = try codeLengthTable.decode(reader: &reader)
            switch symbol {
            case 0 ... 15:
                lengths[i] = symbol
                i += 1
            case 16:
                guard i > 0 else {
                    throw KlibFormatError.corruptDeflateStream("repeat with no previous length")
                }
                let previous = lengths[i - 1]
                let repeatCount = try reader.bits(2) + 3
                guard i + repeatCount <= lengths.count else {
                    throw KlibFormatError.corruptDeflateStream("code length repeat overflows table")
                }
                for _ in 0 ..< repeatCount {
                    lengths[i] = previous
                    i += 1
                }
            case 17:
                let repeatCount = try reader.bits(3) + 3
                guard i + repeatCount <= lengths.count else {
                    throw KlibFormatError.corruptDeflateStream("zero repeat overflows table")
                }
                i += repeatCount
            case 18:
                let repeatCount = try reader.bits(7) + 11
                guard i + repeatCount <= lengths.count else {
                    throw KlibFormatError.corruptDeflateStream("zero repeat overflows table")
                }
                i += repeatCount
            default:
                throw KlibFormatError.corruptDeflateStream("invalid code-length symbol \(symbol)")
            }
        }

        let literalTable = try HuffmanTable(codeLengths: Array(lengths.prefix(literalCount)))
        let distanceTable = try HuffmanTable(codeLengths: Array(lengths.suffix(distanceCount)))
        return (literalTable, distanceTable)
    }

    // MARK: - Compressed block body

    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10,
        11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115,
        131, 163, 195, 227, 258,
    ]

    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4,
        5, 5, 5, 5, 0,
    ]

    private static let distanceBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13,
        17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073,
        4097, 6145, 8193, 12289, 16385, 24577,
    ]

    private static let distanceExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2,
        3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10,
        11, 11, 12, 12, 13, 13,
    ]

    private static func inflateHuffman(
        reader: inout BitReader,
        into output: inout [UInt8],
        literalTable: HuffmanTable,
        distanceTable: HuffmanTable
    ) throws {
        while true {
            let symbol = try literalTable.decode(reader: &reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { break }
            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count else {
                throw KlibFormatError.corruptDeflateStream("invalid length symbol \(symbol)")
            }
            let lengthExtraBits = try reader.bits(lengthExtra[lengthIndex])
            let length = lengthBase[lengthIndex] + lengthExtraBits
            let distanceSymbol = try distanceTable.decode(reader: &reader)
            guard distanceSymbol < distanceBase.count else {
                throw KlibFormatError.corruptDeflateStream("invalid distance symbol \(distanceSymbol)")
            }
            let distanceExtraBits = try reader.bits(distanceExtra[distanceSymbol])
            let distance = distanceBase[distanceSymbol] + distanceExtraBits
            guard distance <= output.count else {
                throw KlibFormatError.corruptDeflateStream("distance \(distance) exceeds output")
            }
            output.reserveCapacity(output.count + length)
            let sourceStart = output.count - distance
            for i in 0 ..< length {
                output.append(output[sourceStart + i])
            }
        }
    }
}
