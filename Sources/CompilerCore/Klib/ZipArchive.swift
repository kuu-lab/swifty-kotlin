import Foundation

/// Minimal read-only zip archive reader.
///
/// Kotlin `.klib` libraries are zip files with a fixed directory layout
/// (`default/manifest`, `default/ir/...`). Foundation provides no zip support
/// and the package has no external dependencies, so this parses the central
/// directory and inflates entries directly.
///
/// Limitations (none apply to real .klib files): multi-disk archives and
/// ZIP64 are rejected; only `stored` and `deflate` compression are supported.
package struct ZipArchive {
    package struct Entry {
        /// Entry path, using `/` separators (e.g. `default/manifest`).
        package let name: String
        /// 0 = stored, 8 = deflate.
        package let compressionMethod: UInt16
        package let compressedSize: Int
        package let uncompressedSize: Int
        package let crc32: UInt32
        package var isDirectory: Bool { name.hasSuffix("/") }

        /// Absolute range of the compressed payload inside the archive.
        let dataRange: Range<Int>
    }

    private let bytes: [UInt8]
    private let entryOffsetsByName: [String: Int]

    /// Central-directory order is preserved.
    package let entries: [Entry]

    package init(data: Data) throws {
        try self.init(bytes: Array(data))
    }

    package init(bytes: [UInt8]) throws {
        self.bytes = bytes

        let eocdOffset = try ZipArchive.findEndOfCentralDirectory(in: bytes)
        let totalEntries = Int(try Self.u16(bytes, eocdOffset + 10))
        let directorySize = Int(try Self.u32(bytes, eocdOffset + 12))
        var directoryOffset = Int(try Self.u32(bytes, eocdOffset + 16))
        guard eocdOffset + 22 <= bytes.count,
              directoryOffset >= 0,
              directoryOffset + directorySize <= bytes.count
        else {
            throw KlibFormatError.truncatedArchive
        }
        // Multi-disk archives are rejected: disk fields must all be zero and
        // the two entry counts must agree.
        let diskNumber = try Self.u16(bytes, eocdOffset + 4)
        let cdStartDisk = try Self.u16(bytes, eocdOffset + 6)
        let entriesThisDisk = try Self.u16(bytes, eocdOffset + 8)
        guard diskNumber == 0, cdStartDisk == 0, entriesThisDisk == UInt16(totalEntries) else {
            throw KlibFormatError.unsupportedMultiDisk
        }

        var entries: [Entry] = []
        entries.reserveCapacity(totalEntries)
        var offsetsByName: [String: Int] = [:]

        for _ in 0 ..< totalEntries {
            guard directoryOffset + 46 <= bytes.count,
                  try Self.u32(bytes, directoryOffset) == 0x0201_4B50
            else {
                throw KlibFormatError.truncatedArchive
            }
            let flags = try Self.u16(bytes, directoryOffset + 8)
            let method = try Self.u16(bytes, directoryOffset + 10)
            let crc = try Self.u32(bytes, directoryOffset + 16)
            let compressedSizeRaw = try Self.u32(bytes, directoryOffset + 20)
            let uncompressedSizeRaw = try Self.u32(bytes, directoryOffset + 24)
            let nameLength = Int(try Self.u16(bytes, directoryOffset + 28))
            let extraLength = Int(try Self.u16(bytes, directoryOffset + 30))
            let commentLength = Int(try Self.u16(bytes, directoryOffset + 32))
            let localHeaderOffset = Int(try Self.u32(bytes, directoryOffset + 42))
            let nameStart = directoryOffset + 46
            guard nameStart + nameLength <= bytes.count else {
                throw KlibFormatError.truncatedArchive
            }
            let name = String(decoding: bytes[nameStart ..< nameStart + nameLength], as: UTF8.self)
            if compressedSizeRaw == 0xFFFF_FFFF || uncompressedSizeRaw == 0xFFFF_FFFF
                || localHeaderOffset == 0xFFFF_FFFF
            {
                throw KlibFormatError.unsupportedZip64
            }
            _ = flags // bit 3 (data descriptor) is legal; sizes come from the central directory.

            let dataOffset = try Self.localDataOffset(in: bytes, at: localHeaderOffset, name: name)
            let compressedSize = Int(compressedSizeRaw)
            guard dataOffset >= 0, dataOffset + compressedSize <= bytes.count else {
                throw KlibFormatError.truncatedArchive
            }

            offsetsByName[name] = entries.count
            entries.append(Entry(
                name: name,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: Int(uncompressedSizeRaw),
                crc32: crc,
                dataRange: dataOffset ..< dataOffset + compressedSize
            ))

            directoryOffset = nameStart + nameLength + extraLength + commentLength
        }

        self.entries = entries
        self.entryOffsetsByName = offsetsByName
    }

    package func entry(named path: String) -> Entry? {
        entryOffsetsByName[path].map { entries[$0] }
    }

    /// Returns the uncompressed contents of an entry, inflating if needed and
    /// validating size and CRC-32.
    package func contents(of entry: Entry) throws -> [UInt8] {
        let compressed = bytes[entry.dataRange]
        let contents: [UInt8]
        switch entry.compressionMethod {
        case 0:
            contents = Array(compressed)
        case 8:
            contents = try Inflater.inflate(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw KlibFormatError.unsupportedCompressionMethod(entry.compressionMethod)
        }
        guard contents.count == entry.uncompressedSize else {
            throw KlibFormatError.sizeMismatch(
                "\(entry.name): \(contents.count) != \(entry.uncompressedSize)"
            )
        }
        guard ZipArchive.crc32(contents) == entry.crc32 else {
            throw KlibFormatError.crcMismatch(entry.name)
        }
        return contents
    }

    // MARK: - Parsing helpers

    private static func findEndOfCentralDirectory(in bytes: [UInt8]) throws -> Int {
        // EOCD is 22 bytes + optional comment (up to 64KiB). Scan backwards
        // for the signature PK\x05\x06.
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        guard bytes.count >= 22 else {
            throw KlibFormatError.notAZipArchive
        }
        let lowerBound = max(0, bytes.count - 22 - 65_536)
        var candidate = bytes.count - 22
        while candidate >= lowerBound {
            if bytes[candidate] == signature[0],
               bytes[candidate + 1] == signature[1],
               bytes[candidate + 2] == signature[2],
               bytes[candidate + 3] == signature[3]
            {
                // Sanity: the declared comment length must reach the end.
                let commentLength = Int((try? u16(bytes, candidate + 20)) ?? 0)
                if candidate + 22 + commentLength == bytes.count {
                    return candidate
                }
            }
            candidate -= 1
        }
        throw KlibFormatError.notAZipArchive
    }

    private static func localDataOffset(in bytes: [UInt8], at localHeaderOffset: Int, name: String) throws -> Int {
        guard localHeaderOffset + 30 <= bytes.count,
              try Self.u32(bytes, localHeaderOffset) == 0x0403_4B50
        else {
            throw KlibFormatError.corruptLocalHeader(name)
        }
        let nameLength = Int(try u16(bytes, localHeaderOffset + 26))
        let extraLength = Int(try u16(bytes, localHeaderOffset + 28))
        let dataOffset = localHeaderOffset + 30 + nameLength + extraLength
        guard dataOffset <= bytes.count else {
            throw KlibFormatError.truncatedArchive
        }
        return dataOffset
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else {
            throw KlibFormatError.truncatedArchive
        }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else {
            throw KlibFormatError.truncatedArchive
        }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    // MARK: - CRC-32 (IEEE, table-driven)

    private static let crcTable: [UInt32] = (0 ..< 256).map { value in
        var crc = UInt32(value)
        for _ in 0 ..< 8 {
            crc = (crc & 1 == 1) ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
        return crc
    }

    package static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
