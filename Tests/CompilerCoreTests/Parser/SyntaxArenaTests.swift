@testable import CompilerCore
import XCTest

final class SyntaxArenaTests: XCTestCase {
    func testAppendTokenAndMakeNodeRoundTrip() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let tokenIDA = arena.appendToken(tokenA)
        let tokenIDB = arena.appendToken(tokenB)

        XCTAssertEqual(tokenIDA, TokenID(rawValue: 0))
        XCTAssertEqual(tokenIDB, TokenID(rawValue: 1))

        let range = makeRange(start: 0, end: 3)
        let nodeID = arena.appendNode(kind: .callExpr, range: range, [.token(tokenIDA), .token(tokenIDB)])
        let node = arena.node(nodeID)

        XCTAssertEqual(node.kind, .callExpr)
        XCTAssertEqual(node.range, range)
        XCTAssertEqual(node.firstChildIndex, 0)
        XCTAssertEqual(node.childCount, 2)

        XCTAssertEqual(Array(arena.children(of: nodeID)), [.token(tokenIDA), .token(tokenIDB)])
    }

    func testNodeReturnsSentinelForInvalidIDs() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let token = makeToken(kind: .identifier(interner.intern("real")), start: 0, end: 4)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 4), [.token(tokenID)])

        let negative = arena.node(NodeID(rawValue: -1))
        XCTAssertEqual(negative.kind, .statement)
        XCTAssertEqual(negative.range.start.file, .invalid)
        XCTAssertEqual(negative.childCount, 0)

        let tooLarge = arena.node(NodeID(rawValue: 999))
        XCTAssertEqual(tooLarge.kind, .statement)
        XCTAssertEqual(tooLarge.range.end.file, .invalid)

        _ = arena.node(NodeID(rawValue: Int32.max))
        _ = arena.children(of: NodeID(rawValue: -50))
        _ = arena.children(of: NodeID(rawValue: Int32.max))

        let node = arena.node(nodeID)
        XCTAssertEqual(node.kind, .callExpr)
        XCTAssertEqual(Array(arena.children(of: nodeID)), [.token(tokenID)])
        XCTAssertEqual(arena.tokens.count, 1)
        XCTAssertEqual(arena.nodes.count, 1)
    }

    func testChildrenReturnsEmptyForNodesWithoutAddressableChildren() {
        let arena = SyntaxArena()
        let emptyNode = arena.appendNode(kind: .block, range: makeRange(), [])

        XCTAssertEqual(Array(arena.children(of: emptyNode)), [])
        XCTAssertEqual(Array(arena.children(of: NodeID(rawValue: 1234))), [])
    }

    func testDeeplyNestedNodeStructure() throws {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let depth = 10

        let leafToken = makeToken(kind: .identifier(interner.intern("leaf")), start: 0, end: 4)
        let leafTokenID = arena.appendToken(leafToken)

        var currentChild: SyntaxChild = .token(leafTokenID)
        var allNodeIDs: [NodeID] = []

        for level in 0 ..< depth {
            let range = makeRange(start: level, end: level + 1)
            let nodeID = arena.appendNode(kind: .block, range: range, [currentChild])
            allNodeIDs.append(nodeID)
            currentChild = .node(nodeID)
        }

        let outermost = try arena.node(XCTUnwrap(allNodeIDs.last))
        XCTAssertEqual(outermost.kind, .block)
        XCTAssertEqual(outermost.childCount, 1)

        var currentNodeID = try XCTUnwrap(allNodeIDs.last)
        for level in stride(from: depth - 1, through: 0, by: -1) {
            let node = arena.node(currentNodeID)
            XCTAssertEqual(node.kind, .block)
            XCTAssertEqual(node.range.start.offset, level)

            let nodeChildren = Array(arena.children(of: currentNodeID))
            XCTAssertEqual(nodeChildren.count, 1)

            if level > 0 {
                if case let .node(childNodeID) = nodeChildren[0] {
                    currentNodeID = childNodeID
                } else {
                    XCTFail("Expected node child at level \(level), got token")
                }
            } else {
                XCTAssertEqual(nodeChildren[0], .token(leafTokenID))
            }
        }
    }

    func testTokensArrayDirectAccess() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("x")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("y")), start: 2, end: 3)
        let tokenC = makeToken(kind: .identifier(interner.intern("z")), start: 4, end: 5)

        let idA = arena.appendToken(tokenA)
        let idB = arena.appendToken(tokenB)
        let idC = arena.appendToken(tokenC)

        XCTAssertEqual(arena.tokens.count, 3)
        XCTAssertEqual(arena.tokens[Int(idA.rawValue)], tokenA)
        XCTAssertEqual(arena.tokens[Int(idB.rawValue)], tokenB)
        XCTAssertEqual(arena.tokens[Int(idC.rawValue)], tokenC)

        XCTAssertEqual(arena.tokens[0].range.start.offset, 0)
        XCTAssertEqual(arena.tokens[1].range.start.offset, 2)
        XCTAssertEqual(arena.tokens[2].range.start.offset, 4)
    }

    func testChildrenArrayDirectAccess() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let tokenA = makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1)
        let tokenB = makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3)
        let idA = arena.appendToken(tokenA)
        let idB = arena.appendToken(tokenB)

        let node1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(idA), .token(idB)])
        let node2 = arena.appendNode(kind: .block, range: makeRange(start: 0, end: 5), [.node(node1)])

        XCTAssertEqual(arena.children.count, 3)
        XCTAssertEqual(arena.children[0], .token(idA))
        XCTAssertEqual(arena.children[1], .token(idB))
        XCTAssertEqual(arena.children[2], .node(node1))

        XCTAssertEqual(Array(arena.children(of: node1)), [.token(idA), .token(idB)])
        XCTAssertEqual(Array(arena.children(of: node2)), [.node(node1)])
    }

    func testChildrenSafetyWhenFirstChildIndexExceedsBounds() {
        let arena = SyntaxArena()
        let nodeID = arena.appendNode(kind: .statement, range: makeRange(), [])

        let sentinel = arena.node(NodeID(rawValue: 9999))
        XCTAssertEqual(sentinel.firstChildIndex, 0)
        XCTAssertEqual(sentinel.childCount, 0)
        XCTAssertEqual(Array(arena.children(of: NodeID(rawValue: 9999))), [])

        XCTAssertEqual(Array(arena.children(of: nodeID)), [])
    }

    func testChildrenSafetyClampingEndBeyondArray() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let token = makeToken(kind: .identifier(interner.intern("x")), start: 0, end: 1)
        let tokenID = arena.appendToken(token)
        let nodeID = arena.appendNode(kind: .callExpr, range: makeRange(), [.token(tokenID)])

        XCTAssertEqual(Array(arena.children(of: nodeID)), [.token(tokenID)])

        // end = firstChildIndex + childCount == children.count — boundary case for clamping
        let node = arena.node(nodeID)
        XCTAssertEqual(node.firstChildIndex, 0)
        XCTAssertEqual(node.childCount, 1)
        XCTAssertEqual(arena.children.count, 1)
    }

    func testMultipleNodesShareChildrenArray() {
        let arena = SyntaxArena()
        let interner = StringInterner()

        let t1 = arena.appendToken(makeToken(kind: .identifier(interner.intern("a")), start: 0, end: 1))
        let t2 = arena.appendToken(makeToken(kind: .identifier(interner.intern("b")), start: 2, end: 3))
        let t3 = arena.appendToken(makeToken(kind: .identifier(interner.intern("c")), start: 4, end: 5))

        let n1 = arena.appendNode(kind: .callExpr, range: makeRange(start: 0, end: 3), [.token(t1), .token(t2)])
        let n2 = arena.appendNode(kind: .statement, range: makeRange(start: 4, end: 5), [.token(t3)])

        XCTAssertEqual(arena.children.count, 3)
        XCTAssertEqual(Array(arena.children(of: n1)), [.token(t1), .token(t2)])
        XCTAssertEqual(Array(arena.children(of: n2)), [.token(t3)])

        let node1 = arena.node(n1)
        let node2 = arena.node(n2)
        XCTAssertEqual(node1.firstChildIndex, 0)
        XCTAssertEqual(node1.childCount, 2)
        XCTAssertEqual(node2.firstChildIndex, 2)
        XCTAssertEqual(node2.childCount, 1)
    }

    func testNodeWithManyChildren() {
        let arena = SyntaxArena()
        let interner = StringInterner()
        let childCount = 20

        var childEntries: [SyntaxChild] = []
        for i in 0 ..< childCount {
            let token = makeToken(kind: .identifier(interner.intern("c\(i)")), start: i, end: i + 1)
            let tokenID = arena.appendToken(token)
            childEntries.append(.token(tokenID))
        }

        let nodeID = arena.appendNode(kind: .block, range: makeRange(start: 0, end: childCount), childEntries)
        let node = arena.node(nodeID)

        XCTAssertEqual(node.childCount, Int16(childCount))
        XCTAssertEqual(node.firstChildIndex, 0)

        let retrievedChildren = Array(arena.children(of: nodeID))
        XCTAssertEqual(retrievedChildren.count, childCount)
        XCTAssertEqual(retrievedChildren.first, childEntries.first)
        XCTAssertEqual(retrievedChildren.last, childEntries.last)
    }
}
