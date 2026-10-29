import Foundation

/// Kotlin writes each chunked `ir/*.kn*` table of a `.klib` as a big-endian
/// `Int32` element count followed by `count` element sizes, then the
/// concatenated element payloads.
/// Since Kotlin 2.4 a *negative* count selects unsigned-LEB128 sizes
/// (`-|count|` elements) instead of fixed `Int32` sizes.
///
/// Three layouts exist:
/// - ``KlibIrTable``: `count` + sizes → `element(i)` (e.g. `files.knf`).
/// - ``KlibIrMultiTable``: an outer table whose rows each embed another
///   table → `element(row, column)` (`bodies.knb`, `types.knt`, `signatures.knt`,
///   `strings.knt`, `fileEntries.knf`, `debugInfo.knd`).
/// - ``KlibIrDeclarationTable`` / ``KlibIrDeclarationMultiTable``: rows keyed
///   by declaration id — `count` followed by `(declId, offset, size)`
///   triples (`irDeclarations.knd`).

package enum KlibChunkIO {
    package static func readInt32(_ bytes: [UInt8], at offset: Int) throws -> Int32 {
        guard offset >= 0, bytes.count >= 4, offset <= bytes.count - 4 else {
            throw KlibFormatError.corruptChunk("truncated Int32 at offset \(offset)")
        }
        return Int32(bitPattern: UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3]))
    }

    /// Unsigned LEB128 at `offset`; returns the value and the offset of the
    /// next byte.
    package static func readUVarint(_ bytes: [UInt8], at offset: Int, end: Int? = nil) throws -> (value: UInt32, next: Int) {
        let limit = end ?? bytes.count
        guard offset >= 0, offset <= limit, limit <= bytes.count else {
            throw KlibFormatError.corruptChunk("invalid uvarint bounds at offset \(offset)")
        }
        var result: UInt32 = 0
        var shift: UInt32 = 0
        var position = offset
        while position < limit {
            let byte = bytes[position]
            position += 1
            guard shift < 28 || byte & 0xF0 == 0 else {
                throw KlibFormatError.corruptChunk("uvarint exceeds 32 bits at offset \(offset)")
            }
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, position) }
            shift += 7
            guard shift < 32 else {
                throw KlibFormatError.corruptChunk("uvarint exceeds 32 bits at offset \(offset)")
            }
        }
        throw KlibFormatError.corruptChunk("truncated uvarint at offset \(offset)")
    }

    /// Returns element offsets relative to `start` (`count + 1` entries;
    /// element 0 begins right after the header).
    package static func parseIndexToOffsets(in bytes: [UInt8], at start: Int, end: Int? = nil) throws -> [Int] {
        let limit = end ?? bytes.count
        guard start >= 0, limit <= bytes.count, limit >= 4, start <= limit - 4 else {
            throw KlibFormatError.corruptChunk("truncated table header at offset \(start)")
        }
        var count = try Int(readInt32(bytes, at: start))
        var position = start + 4
        var usesVarint = false
        if count < 0 {
            // Negative count: sizes use unsigned varints (Kotlin 2.4+).
            count = -count
            usesVarint = true
        }
        // Validate the header before allocating an array from untrusted data.
        guard count <= (limit - position) / (usesVarint ? 1 : 4) else {
            throw KlibFormatError.corruptChunk("element count exceeds table header size")
        }
        var offsets = [Int](repeating: 0, count: count + 1)
        for i in 0 ..< count {
            let size: Int
            if usesVarint {
                let (value, next) = try readUVarint(bytes, at: position, end: limit)
                size = Int(value)
                position = next
            } else {
                size = try Int(readInt32(bytes, at: position))
                position += 4
            }
            guard size >= 0, size <= limit - start - offsets[i] else {
                throw KlibFormatError.corruptChunk("invalid element size \(size)")
            }
            offsets[i + 1] = offsets[i] + size
        }
        // Element payloads follow the header immediately.
        guard offsets[count] <= limit - position else {
            throw KlibFormatError.corruptChunk("element data exceeds chunk size")
        }
        let headerSize = position - start
        for i in offsets.indices { offsets[i] += headerSize }
        return offsets
    }
}

/// Single-dimension table (`IrArrayReader` in Kotlin).
package struct KlibIrTable {
    package let bytes: [UInt8]
    /// Element start offsets relative to `start`, `count + 1`.
    package let elementOffsets: [Int]
    private let start: Int

    package init(bytes: [UInt8], at start: Int = 0) throws {
        self.bytes = bytes
        self.start = start
        self.elementOffsets = try KlibChunkIO.parseIndexToOffsets(in: bytes, at: start)
    }

    package var count: Int { elementOffsets.count - 1 }

    package func element(_ index: Int) throws -> ArraySlice<UInt8> {
        guard index >= 0, index < count else {
            throw KlibFormatError.corruptChunk("element index \(index) out of bounds (count \(count))")
        }
        return bytes[(start + elementOffsets[index]) ..< (start + elementOffsets[index + 1])]
    }
}

/// Two-level table (`IrMultiArrayReader`): `element(row, column)` reads the
/// inner table header embedded at the row offset and returns the column
/// element relative to that row.
package struct KlibIrMultiTable {
    package let bytes: [UInt8]
    /// Outer row offsets relative to the buffer start.
    private let rowOffsets: [Int]

    package init(bytes: [UInt8]) throws {
        self.bytes = bytes
        self.rowOffsets = try KlibChunkIO.parseIndexToOffsets(in: bytes, at: 0)
    }

    package var rowCount: Int { rowOffsets.count - 1 }

    package func columnCount(row: Int) throws -> Int {
        try innerOffsets(row: row).count - 1
    }

    package func element(row: Int, column: Int) throws -> ArraySlice<UInt8> {
        let rowOffset = try checkedRowOffset(row)
        let inner = try innerOffsets(row: row)
        guard column >= 0, column < inner.count - 1 else {
            throw KlibFormatError.corruptChunk("column index \(column) out of bounds (row \(row) has \(inner.count - 1))")
        }
        return bytes[(rowOffset + inner[column]) ..< (rowOffset + inner[column + 1])]
    }

    private func checkedRowOffset(_ row: Int) throws -> Int {
        guard row >= 0, row < rowCount else {
            throw KlibFormatError.corruptChunk("row index \(row) out of bounds (rows \(rowCount))")
        }
        return rowOffsets[row]
    }

    private func innerOffsets(row: Int) throws -> [Int] {
        try KlibChunkIO.parseIndexToOffsets(in: bytes, at: checkedRowOffset(row), end: rowOffsets[row + 1])
    }
}

/// Declaration-id keyed coordinate table (`DeclarationIdTableReader`):
/// `count` followed by `count` `(declId, offset, size)` Int32 triples;
/// offsets are relative to the table start.
package struct KlibIrDeclarationTable {
    package struct Coordinates {
        package let offset: Int
        package let size: Int
    }

    package let bytes: [UInt8]
    package let start: Int
    package let coordinates: [Int32: Coordinates]

    package init(bytes: [UInt8], at start: Int = 0, end: Int? = nil) throws {
        self.bytes = bytes
        self.start = start
        let limit = end ?? bytes.count
        guard start >= 0, limit <= bytes.count, limit >= 4, start <= limit - 4 else {
            throw KlibFormatError.corruptChunk("truncated declaration header")
        }
        let count = try Int(KlibChunkIO.readInt32(bytes, at: start))
        guard count >= 0, count <= (limit - start - 4) / 12 else {
            throw KlibFormatError.corruptChunk("invalid declaration count \(count)")
        }
        let headerSize = 4 + count * 12
        var coordinates: [Int32: Coordinates] = [:]
        coordinates.reserveCapacity(count)
        var position = start + 4
        for _ in 0 ..< count {
            let declId = try KlibChunkIO.readInt32(bytes, at: position)
            let offset = try Int(KlibChunkIO.readInt32(bytes, at: position + 4))
            let size = try Int(KlibChunkIO.readInt32(bytes, at: position + 8))
            guard offset >= headerSize, offset <= limit - start,
                  size >= 0, size <= limit - start - offset else {
                throw KlibFormatError.corruptChunk("declaration \(declId) coordinates out of bounds")
            }
            guard coordinates[declId] == nil else {
                throw KlibFormatError.corruptChunk("duplicate declaration id \(declId)")
            }
            coordinates[declId] = Coordinates(offset: offset, size: size)
            position += 12
        }
        self.coordinates = coordinates
    }

    package var count: Int { coordinates.count }

    package func element(_ declarationId: Int32) throws -> ArraySlice<UInt8> {
        guard let coordinate = coordinates[declarationId] else {
            throw KlibFormatError.corruptChunk("no coordinates for declaration id \(declarationId)")
        }
        return bytes[(start + coordinate.offset) ..< (start + coordinate.offset + coordinate.size)]
    }
}

/// Per-file declaration-id table (`DeclarationIdMultiTableReader`):
/// `element(fileIndex, declId)` reads the coordinate header embedded at the
/// row offset, then the element relative to that row.
package struct KlibIrDeclarationMultiTable {
    package let bytes: [UInt8]
    private let rowOffsets: [Int]

    package init(bytes: [UInt8]) throws {
        self.bytes = bytes
        self.rowOffsets = try KlibChunkIO.parseIndexToOffsets(in: bytes, at: 0)
    }

    package var fileCount: Int { rowOffsets.count - 1 }

    package func declarationIds(fileIndex: Int) throws -> [Int32] {
        try declarationTable(fileIndex: fileIndex).coordinates.keys.sorted()
    }

    package func element(fileIndex: Int, declarationId: Int32) throws -> ArraySlice<UInt8> {
        try declarationTable(fileIndex: fileIndex).element(declarationId)
    }

    private func declarationTable(fileIndex: Int) throws -> KlibIrDeclarationTable {
        guard fileIndex >= 0, fileIndex < fileCount else {
            throw KlibFormatError.corruptChunk("file index \(fileIndex) out of bounds (files \(fileCount))")
        }
        return try KlibIrDeclarationTable(bytes: bytes, at: rowOffsets[fileIndex], end: rowOffsets[fileIndex + 1])
    }
}
