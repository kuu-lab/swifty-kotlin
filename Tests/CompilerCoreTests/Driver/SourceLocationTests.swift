#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SourceLocationTests {
    // MARK: - TokenID

    @Test
    func testTokenIDDefaultIsInvalid() {
        let id = TokenID()
        #expect(id == TokenID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testTokenIDWithRawValue() {
        let id = TokenID(rawValue: 42)
        #expect(id.rawValue == 42)
    }

    @Test
    func testTokenIDEquality() {
        let a = TokenID(rawValue: 5)
        let b = TokenID(rawValue: 5)
        let c = TokenID(rawValue: 6)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testTokenIDHashable() {
        let a = TokenID(rawValue: 10)
        let b = TokenID(rawValue: 10)
        var set = Set<TokenID>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    @Test
    func testTokenIDZero() {
        let id = TokenID(rawValue: 0)
        #expect(id.rawValue == 0)
        #expect(id != TokenID.invalid)
    }

    // MARK: - NodeID

    @Test
    func testNodeIDDefaultIsInvalid() {
        let id = NodeID()
        #expect(id == NodeID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testNodeIDWithRawValue() {
        let id = NodeID(rawValue: 99)
        #expect(id.rawValue == 99)
    }

    @Test
    func testNodeIDEquality() {
        let a = NodeID(rawValue: 3)
        let b = NodeID(rawValue: 3)
        let c = NodeID(rawValue: 4)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testNodeIDHashable() {
        let a = NodeID(rawValue: 7)
        let b = NodeID(rawValue: 7)
        var set = Set<NodeID>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - DeclID

    @Test
    func testDeclIDDefaultIsInvalid() {
        let id = DeclID()
        #expect(id == DeclID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testDeclIDWithRawValue() {
        let id = DeclID(rawValue: 100)
        #expect(id.rawValue == 100)
    }

    @Test
    func testDeclIDEquality() {
        let a = DeclID(rawValue: 1)
        let b = DeclID(rawValue: 1)
        let c = DeclID(rawValue: 2)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testDeclIDHashable() {
        let a = DeclID(rawValue: 50)
        let b = DeclID(rawValue: 50)
        var set = Set<DeclID>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - FileID

    @Test
    func testFileIDDefaultIsInvalid() {
        let id = FileID()
        #expect(id == FileID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testFileIDWithInt32RawValue() {
        let id = FileID(rawValue: Int32(25))
        #expect(id.rawValue == 25)
    }

    @Test
    func testFileIDWithIntRawValue() {
        let id = FileID(rawValue: 30)
        #expect(id.rawValue == 30)
    }

    @Test
    func testFileIDEquality() {
        let a = FileID(rawValue: 10)
        let b = FileID(rawValue: 10)
        let c = FileID(rawValue: 11)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testFileIDHashable() {
        let a = FileID(rawValue: 20)
        let b = FileID(rawValue: 20)
        var set = Set<FileID>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - SourceLocation

    @Test
    func testSourceLocationInit() {
        let loc = SourceLocation(file: FileID(rawValue: 1), offset: 42)
        #expect(loc.file == FileID(rawValue: 1))
        #expect(loc.offset == 42)
    }

    @Test
    func testSourceLocationEquality() {
        let a = SourceLocation(file: FileID(rawValue: 1), offset: 10)
        let b = SourceLocation(file: FileID(rawValue: 1), offset: 10)
        let c = SourceLocation(file: FileID(rawValue: 2), offset: 10)
        let d = SourceLocation(file: FileID(rawValue: 1), offset: 20)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    // MARK: - SourceRange

    @Test
    func testSourceRangeInit() {
        let start = SourceLocation(file: FileID(rawValue: 0), offset: 0)
        let end = SourceLocation(file: FileID(rawValue: 0), offset: 10)
        let range = SourceRange(start: start, end: end)
        #expect(range.start == start)
        #expect(range.end == end)
    }

    @Test
    func testSourceRangeEquality() {
        let r1 = makeRange(file: FileID(rawValue: 0), start: 0, end: 5)
        let r2 = makeRange(file: FileID(rawValue: 0), start: 0, end: 5)
        let r3 = makeRange(file: FileID(rawValue: 0), start: 0, end: 10)
        #expect(r1 == r2)
        #expect(r1 != r3)
    }

    // MARK: - LineColumn

    @Test
    func testLineColumnInit() {
        let lc = LineColumn(line: 5, column: 10)
        #expect(lc.line == 5)
        #expect(lc.column == 10)
    }

    @Test
    func testLineColumnEquality() {
        let a = LineColumn(line: 1, column: 1)
        let b = LineColumn(line: 1, column: 1)
        let c = LineColumn(line: 2, column: 1)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - ASTNodeID

    @Test
    func testASTNodeIDDefaultIsInvalid() {
        let id = ASTNodeID()
        #expect(id == ASTNodeID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testASTNodeIDWithRawValue() {
        let id = ASTNodeID(rawValue: 77)
        #expect(id.rawValue == 77)
    }

    @Test
    func testASTNodeIDEquality() {
        let a = ASTNodeID(rawValue: 5)
        let b = ASTNodeID(rawValue: 5)
        let c = ASTNodeID(rawValue: 6)
        #expect(a == b)
        #expect(a != c)
    }

    @Test
    func testASTNodeIDHashable() {
        let a = ASTNodeID(rawValue: 12)
        let b = ASTNodeID(rawValue: 12)
        var set = Set<ASTNodeID>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - ExprID

    @Test
    func testExprIDDefaultIsInvalid() {
        let id = ExprID()
        #expect(id == ExprID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testExprIDWithRawValue() {
        let id = ExprID(rawValue: 33)
        #expect(id.rawValue == 33)
    }

    @Test
    func testExprIDEquality() {
        let a = ExprID(rawValue: 8)
        let b = ExprID(rawValue: 8)
        let c = ExprID(rawValue: 9)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - TypeRefID

    @Test
    func testTypeRefIDDefaultIsInvalid() {
        let id = TypeRefID()
        #expect(id == TypeRefID.invalid)
        #expect(id.rawValue == -1)
    }

    @Test
    func testTypeRefIDWithRawValue() {
        let id = TypeRefID(rawValue: 55)
        #expect(id.rawValue == 55)
    }

    @Test
    func testTypeRefIDEquality() {
        let a = TypeRefID(rawValue: 14)
        let b = TypeRefID(rawValue: 14)
        let c = TypeRefID(rawValue: 15)
        #expect(a == b)
        #expect(a != c)
    }
}
#endif
