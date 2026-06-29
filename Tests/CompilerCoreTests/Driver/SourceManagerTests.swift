#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SourceManagerTests {
    @Test
    func testAddFileAndLookupByIDAndEnumeration() {
        let manager = SourceManager()
        let id = manager.addFile(path: "in-memory.kt", contents: Data("line1\nline2".utf8))

        #expect(manager.path(of: id) == "in-memory.kt")
        #expect(String(decoding: manager.contents(of: id), as: UTF8.self) == "line1\nline2")
        #expect(manager.fileCount == 1)
        #expect(manager.fileIDs() == [id])
    }

    @Test
    func testAddFileByPathLoadsContents() throws {
        let manager = SourceManager()

        try withTemporaryFile(contents: "abc") { path in
            let id = try manager.addFile(path: path)
            #expect(manager.path(of: id) == path)
            #expect(String(decoding: manager.contents(of: id), as: UTF8.self) == "abc")
        }
    }

    @Test
    func testAddFileWithSamePathAndSameContentsReusesExistingRecord() {
        let manager = SourceManager()
        let original = Data("line1\nline2".utf8)
        let id0 = manager.addFile(path: "dup.kt", contents: original)
        let id1 = manager.addFile(path: "dup.kt", contents: original)

        #expect(id0 == id1)
        #expect(manager.fileCount == 1)
        #expect(
            String(bytes: manager.contents(of: id0), encoding: .utf8) ==
            "line1\nline2"
        )
    }

    @Test
    func testAddFileWithSamePathAndDifferentContentsUpdatesRecordInPlace() {
        let manager = SourceManager()
        let id = manager.addFile(path: "dup.kt", contents: Data("old\ntext".utf8))
        let reusedID = manager.addFile(path: "dup.kt", contents: Data("new\ncontent\n".utf8))

        #expect(id == reusedID)
        #expect(manager.fileCount == 1)
        #expect(
            String(bytes: manager.contents(of: id), encoding: .utf8) ==
            "new\ncontent\n"
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 12)) ==
            LineColumn(line: 3, column: 1)
        )
    }

    @Test
    func testInvalidFileIDUsesSafeFallbacks() {
        let manager = SourceManager()
        let invalid = FileID(rawValue: 999)

        #expect(manager.contents(of: invalid) == Data())
        #expect(manager.path(of: invalid) == "")

        let loc = SourceLocation(file: invalid, offset: 10)
        #expect(manager.lineColumn(of: loc) == LineColumn(line: 1, column: 1))

        let slice = manager.slice(makeRange(file: invalid, start: 0, end: 10))
        #expect(String(slice) == "")
    }

    @Test
    func testLineColumnClampsOffsetsAndHandlesUnicode() {
        let manager = SourceManager()
        let id = manager.addFile(path: "unicode.kt", contents: Data("a\néx\n".utf8))

        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: -10)) ==
            LineColumn(line: 1, column: 1)
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 1)) ==
            LineColumn(line: 1, column: 2)
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 2)) ==
            LineColumn(line: 2, column: 1)
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 5)) ==
            LineColumn(line: 2, column: 3)
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 6)) ==
            LineColumn(line: 3, column: 1)
        )
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 100)) ==
            LineColumn(line: 3, column: 1)
        )
    }

    @Test
    func testLineColumnReturnsDefaultForEmptyFile() {
        let manager = SourceManager()
        let id = manager.addFile(path: "empty.kt", contents: Data())
        let loc = SourceLocation(file: id, offset: 0)
        #expect(manager.lineColumn(of: loc) == LineColumn(line: 1, column: 1))
    }

    @Test
    func testAddFileByPathThrowsForNonExistentFile() {
        let manager = SourceManager()
        #expect(throws: (any Error).self) { try manager.addFile(path: "/non/existent/file.kt") }
    }

    @Test
    func testNegativeFileIDUsesSafeFallbacks() {
        let manager = SourceManager()
        let negativeID = FileID(rawValue: -1)
        #expect(manager.contents(of: negativeID) == Data())
        #expect(manager.path(of: negativeID) == "")
    }

    @Test
    func testSliceClampsBoundsAndNormalizesInvertedRanges() {
        let manager = SourceManager()
        let id = manager.addFile(path: "slice.kt", contents: Data("abcdef".utf8))

        let sliceA = manager.slice(makeRange(file: id, start: -3, end: 3))
        #expect(String(sliceA) == "abc")

        let sliceB = manager.slice(makeRange(file: id, start: 4, end: 2))
        #expect(String(sliceB) == "")

        let sliceC = manager.slice(makeRange(file: id, start: 2, end: 99))
        #expect(String(sliceC) == "cdef")
    }

    // MARK: - Additional Coverage

    @Test
    func testFileIDsOrderingWithMultipleFiles() {
        let manager = SourceManager()
        let id0 = manager.addFile(path: "first.kt", contents: Data("a".utf8))
        let id1 = manager.addFile(path: "second.kt", contents: Data("b".utf8))
        let id2 = manager.addFile(path: "third.kt", contents: Data("c".utf8))

        let ids = manager.fileIDs()
        #expect(ids == [id0, id1, id2], "fileIDs() should return IDs in insertion order")
        #expect(ids.count == 3)

        // Verify each ID maps back to the correct path
        #expect(manager.path(of: ids[0]) == "first.kt")
        #expect(manager.path(of: ids[1]) == "second.kt")
        #expect(manager.path(of: ids[2]) == "third.kt")
    }

    @Test
    func testSliceWithSameStartAndEndReturnsEmpty() {
        let manager = SourceManager()
        let id = manager.addFile(path: "empty-slice.kt", contents: Data("hello".utf8))

        // start == end at various positions should always yield an empty slice
        for offset in [0, 1, 3, 5] {
            let slice = manager.slice(makeRange(file: id, start: offset, end: offset))
            #expect(String(slice) == "", "slice with start == end at offset \(offset) should be empty")
        }
    }

    @Test
    func testSliceSpanningMultipleLines() {
        let manager = SourceManager()
        let source = "line1\nline2\nline3\n"
        let id = manager.addFile(path: "multiline.kt", contents: Data(source.utf8))

        // Slice spanning from the middle of line1 into line2
        // "ine1\nli" -> offsets 1..<8
        let sliceA = manager.slice(makeRange(file: id, start: 1, end: 8))
        #expect(String(sliceA) == "ine1\nli")

        // Slice spanning all three lines
        let sliceB = manager.slice(makeRange(file: id, start: 0, end: 18))
        #expect(String(sliceB) == source)

        // Slice spanning from line2 into line3
        // "line2\nline3\n" -> offsets 6..<18
        let sliceC = manager.slice(makeRange(file: id, start: 6, end: 18))
        #expect(String(sliceC) == "line2\nline3\n")
    }

    @Test
    func testLineColumnWithUnicodeAcrossMultipleLines() {
        let manager = SourceManager()
        // Line 1: "café\n"  (UTF-8: c=1, a=1, f=1, é=2, \n=1 → 6 bytes)
        // Line 2: "日本語\n" (UTF-8: 日=3, 本=3, 語=3, \n=1 → 10 bytes)
        // Line 3: "ok"     (UTF-8: o=1, k=1 → 2 bytes)
        let source = "café\n日本語\nok"
        let id = manager.addFile(path: "unicode-multiline.kt", contents: Data(source.utf8))

        // Offset 0 → Line 1, Column 1 (start of "café")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 0)) ==
            LineColumn(line: 1, column: 1)
        )

        // Offset 3 → Line 1, Column 4 (before 'é', after "caf")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 3)) ==
            LineColumn(line: 1, column: 4)
        )

        // Offset 5 → Line 1, Column 5 (after 'é' which is 2 UTF-8 bytes, before '\n')
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 5)) ==
            LineColumn(line: 1, column: 5)
        )

        // Offset 6 → Line 2, Column 1 (start of "日本語")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 6)) ==
            LineColumn(line: 2, column: 1)
        )

        // Offset 9 → Line 2, Column 2 (after "日", which is 3 UTF-8 bytes)
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 9)) ==
            LineColumn(line: 2, column: 2)
        )

        // Offset 12 → Line 2, Column 3 (after "日本")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 12)) ==
            LineColumn(line: 2, column: 3)
        )

        // Offset 15 → Line 2, Column 4 (after "日本語", before '\n')
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 15)) ==
            LineColumn(line: 2, column: 4)
        )

        // Offset 16 → Line 3, Column 1 (start of "ok")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 16)) ==
            LineColumn(line: 3, column: 1)
        )

        // Offset 17 → Line 3, Column 2 (after "o")
        #expect(
            manager.lineColumn(of: SourceLocation(file: id, offset: 17)) ==
            LineColumn(line: 3, column: 2)
        )
    }
}
#endif
