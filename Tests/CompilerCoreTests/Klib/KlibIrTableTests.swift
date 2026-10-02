@testable import CompilerCore
import Foundation
import Testing

@Suite
struct KlibIrTableTests {

    /// `count` + `count` Int32 sizes + payloads (Kotlin pre-2.4 layout).
    private static func fixedTable(_ elements: [[UInt8]]) -> [UInt8] {
        var bytes: [UInt8] = []
        appendInt32(&bytes, Int32(elements.count))
        for element in elements { appendInt32(&bytes, Int32(element.count)) }
        for element in elements { bytes += element }
        return bytes
    }

    /// Negative count + unsigned-LEB128 sizes (Kotlin 2.4 layout).
    private static func varintTable(_ elements: [[UInt8]]) -> [UInt8] {
        var bytes: [UInt8] = []
        appendInt32(&bytes, Int32(-elements.count))
        for element in elements { appendUVarint(&bytes, UInt32(element.count)) }
        for element in elements { bytes += element }
        return bytes
    }

    private static func appendInt32(_ bytes: inout [UInt8], _ value: Int32) {
        let big = UInt32(bitPattern: value).bigEndian
        withUnsafeBytes(of: big) { bytes += $0 }
    }

    private static func appendUVarint(_ bytes: inout [UInt8], _ value: UInt32) {
        var value = value
        while true {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
            if value == 0 { break }
        }
    }

    // MARK: - Single table

    @Test
    func readsFixedSizeElements() throws {
        let table = try KlibIrTable(bytes: Self.fixedTable([[1, 2, 3], [9], []]))
        #expect(table.count == 3)
        #expect(Array(try table.element(0)) == [1, 2, 3])
        #expect(Array(try table.element(1)) == [9])
        #expect(Array(try table.element(2)) == [])
    }

    @Test
    func readsVarintSizeElements() throws {
        let elements: [[UInt8]] = [[1, 2, 3], [UInt8](repeating: 7, count: 300)]
        let table = try KlibIrTable(bytes: Self.varintTable(elements))
        #expect(table.count == 2)
        #expect(Array(try table.element(0)) == [1, 2, 3])
        #expect(Array(try table.element(1)) == elements[1])
    }

    @Test
    func rejectsElementIndexOutOfBounds() throws {
        let table = try KlibIrTable(bytes: Self.fixedTable([[1]]))
        #expect(throws: KlibFormatError.self) {
            _ = try table.element(1)
        }
    }

    @Test
    func rejectsTruncatedPayload() {
        var bytes = Self.fixedTable([[1, 2, 3]])
        bytes.removeLast()
        #expect(throws: KlibFormatError.self) {
            _ = try KlibIrTable(bytes: bytes)
        }
    }

    // MARK: - Multi table

    @Test
    func readsMultiTableCells() throws {
        // Two rows; row contents are inner tables.
        let row0 = Self.fixedTable([[10, 11], [12]])
        let row1 = Self.fixedTable([[20]])
        let table = try KlibIrMultiTable(bytes: Self.fixedTable([row0, row1]))
        #expect(table.rowCount == 2)
        #expect(try table.columnCount(row: 0) == 2)
        #expect(try table.columnCount(row: 1) == 1)
        #expect(Array(try table.element(row: 0, column: 0)) == [10, 11])
        #expect(Array(try table.element(row: 0, column: 1)) == [12])
        #expect(Array(try table.element(row: 1, column: 0)) == [20])
    }

    @Test
    func rejectsMultiTableIndexOutOfBounds() throws {
        let table = try KlibIrMultiTable(bytes: Self.fixedTable([Self.fixedTable([[1]])]))
        #expect(throws: KlibFormatError.self) {
            _ = try table.element(row: 0, column: 1)
        }
        #expect(throws: KlibFormatError.self) {
            _ = try table.element(row: 5, column: 0)
        }
    }

    // MARK: - Declaration coordinate tables

    @Test
    func readsDeclarationTable() throws {
        // count=2; (declId, offset, size) triples; offsets relative to
        // table start.
        var bytes: [UInt8] = []
        Self.appendInt32(&bytes, 2)
        let headerSize = 4 + 2 * 12
        Self.appendInt32(&bytes, 7); Self.appendInt32(&bytes, Int32(headerSize)); Self.appendInt32(&bytes, 3)
        Self.appendInt32(&bytes, 42); Self.appendInt32(&bytes, Int32(headerSize + 3)); Self.appendInt32(&bytes, 2)
        bytes += [1, 2, 3]
        bytes += [4, 5]

        let table = try KlibIrDeclarationTable(bytes: bytes)
        #expect(table.count == 2)
        #expect(Array(try table.element(7)) == [1, 2, 3])
        #expect(Array(try table.element(42)) == [4, 5])
        #expect(throws: KlibFormatError.self) {
            _ = try table.element(99)
        }
    }

    @Test
    func readsDeclarationMultiTable() throws {
        // Two file rows; each row is a declaration coordinate table.
        func row(declId: Int32, payload: [UInt8]) -> [UInt8] {
            var row: [UInt8] = []
            Self.appendInt32(&row, 1)
            Self.appendInt32(&row, declId)
            Self.appendInt32(&row, 16) // offset just past the header
            Self.appendInt32(&row, Int32(payload.count))
            row += payload
            return row
        }
        let table = try KlibIrDeclarationMultiTable(
            bytes: Self.fixedTable([row(declId: 3, payload: [0xAA]), row(declId: 9, payload: [0xBB, 0xCC])])
        )
        #expect(table.fileCount == 2)
        #expect(try table.declarationIds(fileIndex: 0) == [3])
        #expect(try table.declarationIds(fileIndex: 1) == [9])
        #expect(Array(try table.element(fileIndex: 0, declarationId: 3)) == [0xAA])
        #expect(Array(try table.element(fileIndex: 1, declarationId: 9)) == [0xBB, 0xCC])
    }
}
