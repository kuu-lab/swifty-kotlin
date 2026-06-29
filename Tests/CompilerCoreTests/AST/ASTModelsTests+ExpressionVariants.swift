#if canImport(Testing)
@testable import CompilerCore
import Testing

extension ASTModelsTests {
    // MARK: - Expr variants

    @Test
    func testExprIntLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.intLiteral(42, r)
        if case let .intLiteral(val, range) = expr {
            #expect(val == 42)
            #expect(range == r)
        } else {
            Issue.record("Expected .intLiteral")
        }
    }

    @Test
    func testExprLongLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.longLiteral(Int64.max, r)
        if case let .longLiteral(val, _) = expr {
            #expect(val == Int64.max)
        } else {
            Issue.record("Expected .longLiteral")
        }
    }

    @Test
    func testExprFloatAndDoubleLiteral() {
        let r = makeRange(start: 0, end: 3)
        let floatExpr = Expr.floatLiteral(3.14, r)
        if case let .floatLiteral(val, _) = floatExpr {
            #expect(val == 3.14)
        } else {
            Issue.record("Expected .floatLiteral")
        }
        let doubleExpr = Expr.doubleLiteral(2.718, r)
        if case let .doubleLiteral(val, _) = doubleExpr {
            #expect(val == 2.718)
        } else {
            Issue.record("Expected .doubleLiteral")
        }
    }

    @Test
    func testExprCharLiteral() {
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.charLiteral(65, r)
        if case let .charLiteral(val, _) = expr {
            #expect(val == 65)
        } else {
            Issue.record("Expected .charLiteral")
        }
    }

    @Test
    func testExprBoolLiteral() {
        let r = makeRange(start: 0, end: 3)
        let trueExpr = Expr.boolLiteral(true, r)
        let falseExpr = Expr.boolLiteral(false, r)
        if case let .boolLiteral(val, _) = trueExpr {
            #expect(val)
        } else {
            Issue.record("Expected .boolLiteral")
        }
        if case let .boolLiteral(val, _) = falseExpr {
            #expect(!(val))
        } else {
            Issue.record("Expected .boolLiteral")
        }
    }

    @Test
    func testExprStringLiteralAndTemplate() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let strExpr = Expr.stringLiteral(interner.intern("hello"), r)
        if case let .stringLiteral(val, _) = strExpr {
            #expect(val == interner.intern("hello"))
        } else {
            Issue.record("Expected .stringLiteral")
        }

        let arena = ASTArena()
        let innerExprID = arena.appendExpr(.intLiteral(1, r))
        let templateExpr = Expr.stringTemplate(
            parts: [.literal(interner.intern("x=")), .expression(innerExprID)],
            range: r
        )
        if case let .stringTemplate(parts, _) = templateExpr {
            #expect(parts.count == 2)
        } else {
            Issue.record("Expected .stringTemplate")
        }
    }

    @Test
    func testExprNameRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 3)
        let expr = Expr.nameRef(interner.intern("myVar"), r)
        if case let .nameRef(name, _) = expr {
            #expect(name == interner.intern("myVar"))
        } else {
            Issue.record("Expected .nameRef")
        }
    }

    @Test
    func testExprControlFlow() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let interner = StringInterner()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let loopVar = interner.intern("i")

        let forExpr = Expr.forExpr(loopVariable: loopVar, iterable: bodyID, body: bodyID, range: r)
        if case let .forExpr(lv, _, _, _, _) = forExpr {
            #expect(lv == loopVar)
        } else { Issue.record("Expected .forExpr") }

        let whileExpr = Expr.whileExpr(condition: condID, body: bodyID, range: r)
        if case let .whileExpr(c, b, _, _) = whileExpr {
            #expect(c == condID)
            #expect(b == bodyID)
        } else { Issue.record("Expected .whileExpr") }

        let doWhileExpr = Expr.doWhileExpr(body: bodyID, condition: condID, range: r)
        if case let .doWhileExpr(b, c, _, _) = doWhileExpr {
            #expect(b == bodyID)
            #expect(c == condID)
        } else { Issue.record("Expected .doWhileExpr") }

        let breakExpr = Expr.breakExpr(range: r)
        if case let .breakExpr(_, range) = breakExpr {
            #expect(range == r)
        } else { Issue.record("Expected .breakExpr") }

        let continueExpr = Expr.continueExpr(range: r)
        if case let .continueExpr(_, range) = continueExpr {
            #expect(range == r)
        } else { Issue.record("Expected .continueExpr") }
    }

    @Test
    func testExprLocalDeclAndAssign() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let initID = arena.appendExpr(.intLiteral(5, r))
        let name = interner.intern("x")
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))

        let localDecl = Expr.localDecl(name: name, isMutable: true, typeAnnotation: typeRefID, initializer: initID, range: r)
        if case let .localDecl(n, mut, ta, init_, _, _) = localDecl {
            #expect(n == name)
            #expect(mut)
            #expect(ta == typeRefID)
            #expect(init_ == initID)
        } else { Issue.record("Expected .localDecl") }

        let localAssign = Expr.localAssign(name: name, value: initID, range: r)
        if case let .localAssign(n, v, _) = localAssign {
            #expect(n == name)
            #expect(v == initID)
        } else { Issue.record("Expected .localAssign") }

        let memberAssign = Expr.memberAssign(receiver: initID, callee: interner.intern("value"), value: initID, range: r)
        if case let .memberAssign(receiver, callee, value, _) = memberAssign {
            #expect(receiver == initID)
            #expect(callee == interner.intern("value"))
            #expect(value == initID)
        } else { Issue.record("Expected .memberAssign") }

        let arrExprID = arena.appendExpr(.intLiteral(0, r))
        let idxExprID = arena.appendExpr(.intLiteral(1, r))
        let indexedAssign = Expr.indexedAssign(receiver: arrExprID, indices: [idxExprID], value: initID, range: r)
        if case let .indexedAssign(a, indices, v, _) = indexedAssign {
            #expect(a == arrExprID)
            #expect(indices == [idxExprID])
            #expect(v == initID)
        } else { Issue.record("Expected .indexedAssign") }
    }

    @Test
    func testExprCallAndMemberCall() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let calleeID = arena.appendExpr(.nameRef(interner.intern("foo"), r))
        let argExprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let arg = CallArgument(label: interner.intern("x"), isSpread: false, expr: argExprID)

        let callExpr = Expr.call(callee: calleeID, typeArgs: [typeRefID], args: [arg], range: r)
        if case let .call(c, ta, args, _) = callExpr {
            #expect(c == calleeID)
            #expect(ta.count == 1)
            #expect(args.count == 1)
            #expect(args[0].label == interner.intern("x"))
        } else { Issue.record("Expected .call") }

        let receiverID = arena.appendExpr(.nameRef(interner.intern("obj"), r))
        let memberCall = Expr.memberCall(receiver: receiverID, callee: interner.intern("bar"), typeArgs: [], args: [arg], range: r)
        if case let .memberCall(recv, callee, _, args, _) = memberCall {
            #expect(recv == receiverID)
            #expect(callee == interner.intern("bar"))
            #expect(args.count == 1)
        } else { Issue.record("Expected .memberCall") }

        let safeMemberCall = Expr.safeMemberCall(receiver: receiverID, callee: interner.intern("baz"), typeArgs: [], args: [], range: r)
        if case let .safeMemberCall(recv, callee, _, _, _) = safeMemberCall {
            #expect(recv == receiverID)
            #expect(callee == interner.intern("baz"))
        } else { Issue.record("Expected .safeMemberCall") }
    }

    @Test
    func testExprIndexedAccess() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let arrID = arena.appendExpr(.intLiteral(0, r))
        let idxID = arena.appendExpr(.intLiteral(1, r))
        let expr = Expr.indexedAccess(receiver: arrID, indices: [idxID], range: r)
        if case let .indexedAccess(a, indices, _) = expr {
            #expect(a == arrID)
            #expect(indices == [idxID])
        } else { Issue.record("Expected .indexedAccess") }
    }

    @Test
    func testExprBinaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let lhs = arena.appendExpr(.intLiteral(1, r))
        let rhs = arena.appendExpr(.intLiteral(2, r))
        let ops: [BinaryOp] = [
            .add, .subtract, .multiply, .divide, .modulo,
            .equal, .notEqual, .lessThan, .lessOrEqual,
            .greaterThan, .greaterOrEqual, .logicalAnd,
            .logicalOr, .elvis, .rangeTo,
        ]
        for op in ops {
            let expr = Expr.binary(op: op, lhs: lhs, rhs: rhs, range: r)
            if case let .binary(o, _, _, _) = expr {
                #expect(o == op)
            } else { Issue.record("Expected .binary for op \(op)") }
        }
    }

    @Test
    func testExprUnaryAllOps() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let operand = arena.appendExpr(.intLiteral(1, r))
        let ops: [UnaryOp] = [.not, .unaryPlus, .unaryMinus]
        for op in ops {
            let expr = Expr.unaryExpr(op: op, operand: operand, range: r)
            if case let .unaryExpr(o, _, _) = expr {
                #expect(o == op)
            } else { Issue.record("Expected .unaryExpr for op \(op)") }
        }
    }

    @Test
    func testExprCompoundAssignAllOps() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))
        let name = interner.intern("x")
        let ops: [CompoundAssignOp] = [.plusAssign, .minusAssign, .timesAssign, .divAssign, .modAssign]
        for op in ops {
            let expr = Expr.compoundAssign(op: op, name: name, value: valID, range: r)
            if case let .compoundAssign(o, _, _, _) = expr {
                #expect(o == op)
            } else { Issue.record("Expected .compoundAssign for op \(op)") }
        }
    }
}
#endif
