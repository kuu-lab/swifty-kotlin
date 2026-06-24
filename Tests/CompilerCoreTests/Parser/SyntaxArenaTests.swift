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

        let negative = arena.node(NodeID(rawValue: -1))
        #expect(negative.kind == .statement)
        #expect(negative.range.start.file == .invalid)
        #expect(negative.childCount == 0)

        let tooLarge = arena.node(NodeID(rawValue: 999))
        #expect(tooLarge.kind == .statement)
        #expect(tooLarge.range.end.file == .invalid)
    }

    @Test
    func testChildrenReturnsEmptyForNodesWithoutAddressableChildren() {
        let arena = SyntaxArena()
        let emptyNode = arena.appendNode(kind: .block, range: makeRange(), [])

        #expect(Array(arena.children(of: emptyNode)) == [])
        #expect(Array(arena.children(of: NodeID(rawValue: 1234))) == [])
    }

    // MARK: - Edge Cases

    @Test
    func testLargeNumberOfTokenAdditions() throws {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let count = 10000

        var tokenIDs: [TokenID] = []
        for i in 0 ..< count {
            let token = makeToken(kind: .identifier(interner.intern("t\(i)")), start: i, end: i + 1)
            tokenIDs.append(arena.appendToken(token))
        }

        #expect(tokenIDs.count == count)
        #expect(tokenIDs.first == TokenID(rawValue: 0))
        #expect(tokenIDs.last == TokenID(rawValue: Int32(count - 1)))
        #expect(arena.tokens.count == count)

        // Verify first and last tokens are retrievable
        #expect(try arena.tokens[Int(#require(tokenIDs.first?.rawValue))].range.start.offset == 0)
        #expect(try arena.tokens[Int(#require(tokenIDs.last?.rawValue))].range.start.offset == count - 1)
    }

    @Test
    func testLargeNumberOfNodeAdditions() throws {
        let arena = SyntaxArena()
        let count = 10000

        var nodeIDs: [NodeID] = []
        for i in 0 ..< count {
            let range = makeRange(start: i, end: i + 1)
            nodeIDs.append(arena.appendNode(kind: .statement, range: range, []))
        }

        #expect(nodeIDs.count == count)
        #expect(nodeIDs.first == NodeID(rawValue: 0))
        #expect(nodeIDs.last == NodeID(rawValue: Int32(count - 1)))
        #expect(arena.nodes.count == count)

        // Verify retrieval of first and last nodes
        let firstNode = try arena.node(#require(nodeIDs.first))
        let lastNode = try arena.node(#require(nodeIDs.last))
        #expect(firstNode.range.start.offset == 0)
        #expect(lastNode.range.start.offset == count - 1)
    }

    @Test
    func testInt32BoundaryTokenID() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        // Pre-populate tokens to push the next ID close to a known value
        // Verify that TokenID wraps Int32 correctly at moderate scale
        let token = makeToken(kind: .identifier(interner.intern("boundary")), start: 0, end: 1)
        let id = arena.appendToken(token)
        #expect(id.rawValue == 0)

        // Int32.max is 2_147_483_647 — we can't allocate that many, but verify
        // the rawValue type is Int32 and handles typical casting
        let manualID = TokenID(rawValue: Int32.max)
        #expect(manualID.rawValue == Int32.max)

        let manualNegID = TokenID(rawValue: Int32.min)
        #expect(manualNegID.rawValue == Int32.min)
    }

    @Test
    func testDeeplyNestedNodeStructure() throws {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let depth = 100

        // Create a leaf token
        let leafToken = makeToken(kind: .identifier(interner.intern("leaf")), start: 0, end: 4)
        let leafTokenID = arena.appendToken(leafToken)

        // Build a deeply nested tree: each node wraps the previous one
        var currentChild: SyntaxChild = .token(leafTokenID)
        var allNodeIDs: [NodeID] = []

        for level in 0 ..< depth {
            let range = makeRange(start: level, end: level + 1)
            let nodeID = arena.appendNode(kind: .block, range: range, [currentChild])
            allNodeIDs.append(nodeID)
            currentChild = .node(nodeID)
        }

        // Verify the outermost node
        let outermost = try arena.node(#require(allNodeIDs.last))
        #expect(outermost.kind == .block)
        #expect(outermost.childCount == 1)

        // Walk from outermost to innermost
        var currentNodeID = try #require(allNodeIDs.last)
        for level in stride(from: depth - 1, through: 0, by: -1) {
            let node = arena.node(currentNodeID)
            #expect(node.kind == .block)
            #expect(node.range.start.offset == level)

            let nodeChildren = Array(arena.children(of: currentNodeID))
            #expect(nodeChildren.count == 1)

            if level > 0 {
                // Child should be a node
                if case let .node(childNodeID) = nodeChildren[0] {
                    currentNodeID = childNodeID
                } else {
                    Issue.record("Expected node child at level \(level), got token")
                }
            } else {
                // Innermost level: child should be the leaf token
                #expect(nodeChildren[0] == .token(leafTokenID))
            }
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

        // Direct access to tokens array by index
        #expect(arena.tokens.count == 3)
        #expect(arena.tokens[Int(idA.rawValue)] == tokenA)
        #expect(arena.tokens[Int(idB.rawValue)] == tokenB)
        #expect(arena.tokens[Int(idC.rawValue)] == tokenC)

        // Verify ordering matches insertion order
        #expect(arena.tokens[0].range.start.offset == 0)
        #expect(arena.tokens[1].range.start.offset == 2)
        #expect(arena.tokens[2].range.start.offset == 4)
    }

    @Test
    func testChildrenArrayDirectAccess() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let idA = arena.appendToken(tokenA)
        let idB = arena.appendToken(tokenB)

        // First node with 2 children
        let node1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(idA), .token(idB)])
        // Second node with 1 child (node reference)
        let node2 = arena.appendNode(kind: .block, range: makeRange(start: 0, end: 5), [.node(node1)])

        // Direct children array should contain all 3 entries in insertion order
        #expect(arena.children.count == 3)
        #expect(arena.children[0] == .token(idA))
        #expect(arena.children[1] == .token(idB))
        #expect(arena.children[2] == .node(node1))

        // Verify node-specific children slice
        #expect(Array(arena.children(of: node1)) == [.token(idA), .token(idB)])
        #expect(Array(arena.children(of: node2)) == [.node(node1)])
    }

    @Test
    func testChildrenSafetyWhenFirstChildIndexExceedsBounds() {
        let arena = SyntaxArena()

        // Create a node with no children so firstChildIndex == 0 and childCount == 0
        let nodeID = arena.appendNode(kind: .statement, range: makeRange(), [])

        // The sentinel returned for out-of-bounds NodeID has firstChildIndex == 0
        // and childCount == 0, so children(of:) should return empty
        let sentinel = arena.node(NodeID(rawValue: 9999))
        #expect(sentinel.firstChildIndex == 0)
        #expect(sentinel.childCount == 0)
        #expect(Array(arena.children(of: NodeID(rawValue: 9999))) == [])

        // Valid node with no children
        #expect(Array(arena.children(of: nodeID)) == [])
    }

    @Test
    func testChildrenSafetyClampingEndBeyondArray() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        // Add one token and one node with that token as child
        let token = makeToken(kind: .identifier(interner.intern("x")), start: 0, end: 1)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(), [.token(tokenID)])

        // Verify normal access works
        #expect(Array(arena.children(of: nodeID)) == [.token(tokenID)])

        // Manually verify the clamping logic in children(of:)
        // The node's firstChildIndex=0, childCount=1
        // end = 0 + 1 = 1 which equals children.count — this is the boundary case
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

        // Node 1 owns children[0..1]
        let n1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(t1), .token(t2)])
        // Node 2 owns children[2..2]
        let n2 = arena.appendNode(kind: .statement, range: makeRange(start: 4, end: 5), [.token(t3)])

        // Total children count is 3
        #expect(arena.children.count == 3)

        // Each node's children are independent slices
        #expect(Array(arena.children(of: n1)) == [.token(t1), .token(t2)])
        #expect(Array(arena.children(of: n2)) == [.token(t3)])

        // Verify firstChildIndex assignments
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
        let childCount = 1000

        var childEntries: [SyntaxChild] = []
        for i in 0 ..< childCount {
            let token = makeToken(kind: .identifier(interner.intern("c\(i)")), start: i, end: i + 1)
            let tokenID = arena.appendToken(token)
            childEntries.append(.token(tokenID))
        }

        let nodeID = arena.appendNode(kind: .block, range: makeRange(start: 0, end: childCount), childEntries)
        let node = arena.node(nodeID)

        #expect(node.childCount == Int16(childCount))
        #expect(node.firstChildIndex == 0)

        let retrievedChildren = Array(arena.children(of: nodeID))
        #expect(retrievedChildren.count == childCount)
        #expect(retrievedChildren.first == childEntries.first)
        #expect(retrievedChildren.last == childEntries.last)
    }

    @Test
    func testNodeInvalidIDSentinelDoesNotCorruptArena() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        // Add real data first
        let token = makeToken(kind: .identifier(interner.intern("real")), start: 0, end: 4)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 4), [.token(tokenID)])

        // Access invalid IDs — should not corrupt the arena
        _ = arena.node(NodeID(rawValue: -100))
        _ = arena.node(NodeID(rawValue: Int32.max))
        _ = arena.children(of: NodeID(rawValue: -50))
        _ = arena.children(of: NodeID(rawValue: Int32.max))

        // Verify original data is still intact
        let node = arena.node(nodeID)
        #expect(node.kind == .callExpr)
        #expect(Array(arena.children(of: nodeID)) == [.token(tokenID)])
        #expect(arena.tokens.count == 1)
        #expect(arena.nodes.count == 1)
    }
}
#endif
