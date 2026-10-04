#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SyntaxArenaTests {
    @Test
    func testAppendTokenAndMakeNodeRoundTrip() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let tokenIDA = arena.appendToken(tokenA)
        let tokenIDB = arena.appendToken(tokenB)

        #expect(tokenIDA == TokenID(rawValue: 0))
        #expect(tokenIDB == TokenID(rawValue: 1))

        let range = makeRange(start: 0, end: 3)
        let nodeID = arena.appendNode(kind: .callExpr, range: range, [.token(tokenIDA), .token(tokenIDB)])
        let node = arena.node(nodeID)

        #expect(node.kind == .callExpr)
        #expect(node.range == range)
        #expect(node.firstChildIndex == 0)
        #expect(node.childCount == 2)

        #expect(Array(arena.children(of: nodeID)) == [.token(tokenIDA), .token(tokenIDB)])
    }

    @Test
    func testNodeReturnsSentinelForInvalidIDs() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let token = makeToken(kind: .identifier(interner.intern("real")), start: 0, end: 4)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 4), [.token(tokenID)])

        let negative = arena.node(NodeID(rawValue: -1))
        #expect(negative.kind == .statement)
        #expect(negative.range.start.file == .invalid)
        #expect(negative.childCount == 0)

        let tooLarge = arena.node(NodeID(rawValue: 999))
        #expect(tooLarge.kind == .statement)
        #expect(tooLarge.range.end.file == .invalid)

        _ = arena.node(NodeID(rawValue: Int32.max))
        _ = arena.children(of: NodeID(rawValue: -50))
        _ = arena.children(of: NodeID(rawValue: Int32.max))

        // Reading through invalid IDs must not disturb the real data.
        let node = arena.node(nodeID)
        #expect(node.kind == .callExpr)
        #expect(Array(arena.children(of: nodeID)) == [.token(tokenID)])
        #expect(arena.tokens.count == 1)
        #expect(arena.nodes.count == 1)
    }

    @Test
    func testChildrenReturnsEmptyForNodesWithoutAddressableChildren() {
        let arena = SyntaxArena()
        let emptyNode = arena.appendNode(kind: .block, range: makeRange(), [])

        #expect(Array(arena.children(of: emptyNode)) == [])
        #expect(Array(arena.children(of: NodeID(rawValue: 1234))) == [])
    }

    @Test
    func testDeeplyNestedNodeStructure() {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let depth = 10

        let leafTokenID = arena.appendToken(
            makeToken(kind: .identifier(interner.intern("leaf")), start: 0, end: 4)
        )

        var currentChild: SyntaxChild = .token(leafTokenID)
        var allNodeIDs: [NodeID] = []
        for level in 0 ..< depth {
            let range = makeRange(start: level, end: level + 1)
            let nodeID = arena.appendNode(kind: .block, range: range, [currentChild])
            allNodeIDs.append(nodeID)
            currentChild = .node(nodeID)
        }

        // Outermost inward: every level wraps exactly the node below it, and
        // the innermost one wraps the leaf token.
        for level in stride(from: depth - 1, through: 0, by: -1) {
            let nodeID = allNodeIDs[level]
            let node = arena.node(nodeID)
            #expect(node.kind == .block)
            #expect(node.range.start.offset == level)

            let expectedChild: SyntaxChild = level > 0 ? .node(allNodeIDs[level - 1]) : .token(leafTokenID)
            #expect(Array(arena.children(of: nodeID)) == [expectedChild])
        }
    }

    @Test
    func testTokensArrayDirectAccess() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("x")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("y")), start: 2, end: 3)
        let tokenC = makeToken(kind: .identifier(interner.intern("z")), start: 4, end: 5)

        let idA = arena.appendToken(tokenA)
        let idB = arena.appendToken(tokenB)
        let idC = arena.appendToken(tokenC)

        #expect(arena.tokens.count == 3)
        #expect(arena.tokens[Int(idA.rawValue)] == tokenA)
        #expect(arena.tokens[Int(idB.rawValue)] == tokenB)
        #expect(arena.tokens[Int(idC.rawValue)] == tokenC)

        #expect(arena.tokens[0].range.start.offset == 0)
        #expect(arena.tokens[1].range.start.offset == 2)
        #expect(arena.tokens[2].range.start.offset == 4)

        // `token(_:)` is the bounds-checked accessor the parser itself uses.
        #expect(arena.token(idB) == tokenB)
        #expect(arena.token(TokenID(rawValue: 3)) == nil)
        #expect(arena.token(TokenID(rawValue: -1)) == nil)
    }

    @Test
    func testChildrenArrayDirectAccess() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let idA = arena.appendToken(tokenA)
        let idB = arena.appendToken(tokenB)

        let node1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(idA), .token(idB)])
        let node2 = arena.appendNode(kind: .block, range: makeRange(start: 0, end: 5), [.node(node1)])

        #expect(arena.children.count == 3)
        #expect(arena.children[0] == .token(idA))
        #expect(arena.children[1] == .token(idB))
        #expect(arena.children[2] == .node(node1))

        #expect(Array(arena.children(of: node1)) == [.token(idA), .token(idB)])
        #expect(Array(arena.children(of: node2)) == [.node(node1)])
    }

    @Test
    func testChildrenSafetyWhenFirstChildIndexExceedsBounds() {
        let arena = SyntaxArena()
        let nodeID = arena.appendNode(kind: .statement, range: makeRange(), [])

        let sentinel = arena.node(NodeID(rawValue: 9999))
        #expect(sentinel.firstChildIndex == 0)
        #expect(sentinel.childCount == 0)
        #expect(Array(arena.children(of: NodeID(rawValue: 9999))) == [])

        #expect(Array(arena.children(of: nodeID)) == [])
    }

    @Test
    func testChildrenSafetyClampingEndBeyondArray() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let token = makeToken(kind: .identifier(interner.intern("x")), start: 0, end: 1)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(), [.token(tokenID)])

        #expect(Array(arena.children(of: nodeID)) == [.token(tokenID)])

        // end = firstChildIndex + childCount == children.count — boundary case for clamping
        let node = arena.node(nodeID)
        #expect(node.firstChildIndex == 0)
        #expect(node.childCount == 1)
        #expect(arena.children.count == 1)
    }

    @Test
    func testMultipleNodesShareChildrenArray() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let t1 = arena.appendToken(makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1))
        let t2 = arena.appendToken(makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3))
        let t3 = arena.appendToken(makeToken(kind: .identifier(interner.intern("c")), start: 4, end: 5))

        let n1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(t1), .token(t2)])
        let n2 = arena.appendNode(kind: .statement, range: makeRange(start: 4, end: 5), [.token(t3)])

        #expect(arena.children.count == 3)
        #expect(Array(arena.children(of: n1)) == [.token(t1), .token(t2)])
        #expect(Array(arena.children(of: n2)) == [.token(t3)])

        let node1 = arena.node(n1)
        let node2 = arena.node(n2)
        #expect(node1.firstChildIndex == 0)
        #expect(node1.childCount == 2)
        #expect(node2.firstChildIndex == 2)
        #expect(node2.childCount == 1)
    }

    @Test
    func testNodeWithManyChildren() {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let childCount = 20
        let name = interner.intern("child")

        var childEntries: [SyntaxChild] = []
        for i in 0 ..< childCount {
            let tokenID = arena.appendToken(makeToken(kind: .identifier(name), start: i, end: i + 1))
            childEntries.append(.token(tokenID))
        }

        let nodeID = arena.appendNode(kind: .block, range: makeRange(start: 0, end: childCount), childEntries)
        let node = arena.node(nodeID)

        #expect(node.childCount == childCount)
        #expect(node.firstChildIndex == 0)

        let retrievedChildren = arena.children(of: nodeID)
        #expect(retrievedChildren.count == childCount)
        #expect(retrievedChildren.first == childEntries.first)
        #expect(retrievedChildren.last == childEntries.last)
    }
}
#endif
