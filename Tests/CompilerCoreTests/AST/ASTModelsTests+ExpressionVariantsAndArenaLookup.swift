#if canImport(Testing)
@testable import CompilerCore
import Testing

extension ASTModelsTests {
    @Test
    func testExprWhenExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let subjectID = arena.appendExpr(.intLiteral(1, r))
        let bodyID = arena.appendExpr(.intLiteral(2, r))
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let elseID = arena.appendExpr(.intLiteral(3, r))
        let branch = WhenBranch(conditions: [condID], body: bodyID, range: r)
        let expr = Expr.whenExpr(subject: subjectID, branches: [branch], elseExpr: elseID, range: r)
        if case let .whenExpr(s, bs, e, _) = expr {
            #expect(s == subjectID)
            #expect(bs.count == 1)
            #expect(e == elseID)
        } else { Issue.record("Expected .whenExpr") }
    }

    @Test
    func testExprReturnAndThrow() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let valID = arena.appendExpr(.intLiteral(1, r))

        let returnWithValue = Expr.returnExpr(value: valID, range: r)
        if case let .returnExpr(v, _, _) = returnWithValue {
            #expect(v == valID)
        } else { Issue.record("Expected .returnExpr") }

        let returnVoid = Expr.returnExpr(value: nil, range: r)
        if case let .returnExpr(v, _, _) = returnVoid {
            #expect(v == nil)
        } else { Issue.record("Expected .returnExpr") }

        let throwExpr = Expr.throwExpr(value: valID, range: r)
        if case let .throwExpr(v, _) = throwExpr {
            #expect(v == valID)
        } else { Issue.record("Expected .throwExpr") }
    }

    @Test
    func testExprIfExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let condID = arena.appendExpr(.boolLiteral(true, r))
        let thenID = arena.appendExpr(.intLiteral(1, r))
        let elseID = arena.appendExpr(.intLiteral(2, r))

        let withElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: elseID, range: r)
        if case let .ifExpr(c, t, e, _) = withElse {
            #expect(c == condID)
            #expect(t == thenID)
            #expect(e == elseID)
        } else { Issue.record("Expected .ifExpr") }

        let withoutElse = Expr.ifExpr(condition: condID, thenExpr: thenID, elseExpr: nil, range: r)
        if case let .ifExpr(_, _, e, _) = withoutElse {
            #expect(e == nil)
        } else { Issue.record("Expected .ifExpr") }
    }

    @Test
    func testExprTryExpr() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let catchBodyID = arena.appendExpr(.intLiteral(2, r))
        let finallyID = arena.appendExpr(.intLiteral(3, r))
        let catchClause = CatchClause(paramName: interner.intern("e"), paramTypeName: interner.intern("Exception"), body: catchBodyID, range: r)

        let tryExpr = Expr.tryExpr(body: bodyID, catchClauses: [catchClause], finallyExpr: finallyID, range: r)
        if case let .tryExpr(b, cc, f, _) = tryExpr {
            #expect(b == bodyID)
            #expect(cc.count == 1)
            #expect(f == finallyID)
        } else { Issue.record("Expected .tryExpr") }
    }

    @Test
    func testExprIsCheckAndAsCast() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))

        let isCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: false, range: r)
        if case let .isCheck(_, _, neg, _) = isCheck {
            #expect(!(neg))
        } else { Issue.record("Expected .isCheck") }

        let isNotCheck = Expr.isCheck(expr: exprID, type: typeRefID, negated: true, range: r)
        if case let .isCheck(_, _, neg, _) = isNotCheck {
            #expect(neg)
        } else { Issue.record("Expected .isCheck negated") }

        let safeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: true, range: r)
        if case let .asCast(_, _, safe, _) = safeCast {
            #expect(safe)
        } else { Issue.record("Expected .asCast safe") }

        let unsafeCast = Expr.asCast(expr: exprID, type: typeRefID, isSafe: false, range: r)
        if case let .asCast(_, _, safe, _) = unsafeCast {
            #expect(!(safe))
        } else { Issue.record("Expected .asCast unsafe") }
    }

    @Test
    func testExprNullAssert() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let exprID = arena.appendExpr(.intLiteral(1, r))
        let nullAssert = Expr.nullAssert(expr: exprID, range: r)
        if case let .nullAssert(e, _) = nullAssert {
            #expect(e == exprID)
        } else { Issue.record("Expected .nullAssert") }
    }

    @Test
    func testExprLambdaLiteral() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let params = [interner.intern("x"), interner.intern("y")]
        let lambda = Expr.lambdaLiteral(params: params, body: bodyID, range: r)
        if case let .lambdaLiteral(p, b, _, _) = lambda {
            #expect(p.count == 2)
            #expect(b == bodyID)
        } else { Issue.record("Expected .lambdaLiteral") }
    }

    @Test
    func testExprObjectLiteral() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let typeRefID = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        let obj = Expr.objectLiteral(superTypes: [typeRefID], decl: nil, range: r)
        if case let .objectLiteral(st, decl, _) = obj {
            #expect(st.count == 1)
            #expect(decl == nil)
        } else { Issue.record("Expected .objectLiteral") }
    }

    @Test
    func testExprCallableRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let receiverID = arena.appendExpr(.nameRef(interner.intern("MyClass"), r))
        let ref = Expr.callableRef(receiver: receiverID, member: interner.intern("method"), range: r)
        if case let .callableRef(recv, member, _) = ref {
            #expect(recv == receiverID)
            #expect(member == interner.intern("method"))
        } else { Issue.record("Expected .callableRef") }

        let refNoReceiver = Expr.callableRef(receiver: nil, member: interner.intern("topFun"), range: r)
        if case let .callableRef(recv, _, _) = refNoReceiver {
            #expect(recv == nil)
        } else { Issue.record("Expected .callableRef without receiver") }
    }

    @Test
    func testExprLocalFunDecl() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let bodyID = arena.appendExpr(.intLiteral(1, r))
        let param = ValueParamDecl(name: interner.intern("a"), type: TypeRefID(rawValue: 0))
        let typeRefID = arena.appendTypeRef(.named(path: [interner.intern("Int")], args: [], nullable: false))
        let localFun = Expr.localFunDecl(name: interner.intern("helper"), valueParams: [param], returnType: typeRefID, body: .expr(bodyID, r), isSuspend: true, range: r)
        if case let .localFunDecl(name, params, ret, body, isSuspend, _) = localFun {
            #expect(name == interner.intern("helper"))
            #expect(params.count == 1)
            #expect(ret == typeRefID)
            #expect(isSuspend)
            if case let .expr(e, _) = body {
                #expect(e == bodyID)
            } else { Issue.record("Expected .expr body") }
        } else { Issue.record("Expected .localFunDecl") }
    }

    @Test
    func testExprBlockExpr() {
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let stmt1 = arena.appendExpr(.intLiteral(1, r))
        let stmt2 = arena.appendExpr(.intLiteral(2, r))
        let trailing = arena.appendExpr(.intLiteral(3, r))
        let block = Expr.blockExpr(statements: [stmt1, stmt2], trailingExpr: trailing, range: r)
        if case let .blockExpr(stmts, trail, _) = block {
            #expect(stmts.count == 2)
            #expect(trail == trailing)
        } else { Issue.record("Expected .blockExpr") }

        let blockNoTrail = Expr.blockExpr(statements: [stmt1], trailingExpr: nil, range: r)
        if case let .blockExpr(_, trail, _) = blockNoTrail {
            #expect(trail == nil)
        } else { Issue.record("Expected .blockExpr without trailing") }
    }

    @Test
    func testExprSuperRefAndThisRef() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 5)
        let superRef = Expr.superRef(interfaceQualifier: nil, r)
        if case let .superRef(qualifier, range) = superRef {
            #expect(qualifier == nil)
            #expect(range == r)
        } else { Issue.record("Expected .superRef") }

        let qualifiedSuperRef = Expr.superRef(interfaceQualifier: interner.intern("MyInterface"), r)
        if case let .superRef(qualifier, range) = qualifiedSuperRef {
            #expect(qualifier == interner.intern("MyInterface"))
            #expect(range == r)
        } else { Issue.record("Expected .superRef with qualifier") }

        let thisRef = Expr.thisRef(label: nil, r)
        if case let .thisRef(label, _) = thisRef {
            #expect(label == nil)
        } else { Issue.record("Expected .thisRef") }

        let thisRefLabeled = Expr.thisRef(label: interner.intern("Outer"), r)
        if case let .thisRef(label, _) = thisRefLabeled {
            #expect(label == interner.intern("Outer"))
        } else { Issue.record("Expected .thisRef with label") }
    }

    // MARK: - ASTArena expr() method

    @Test
    func testASTArenaExprLookup() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(42, r))
        let id1 = arena.appendExpr(.boolLiteral(true, r))

        if case let .intLiteral(val, _) = arena.expr(id0) {
            #expect(val == 42)
        } else {
            Issue.record("Expected .intLiteral from arena.expr()")
        }

        if case let .boolLiteral(val, _) = arena.expr(id1) {
            #expect(val)
        } else {
            Issue.record("Expected .boolLiteral from arena.expr()")
        }
    }

    @Test
    func testASTArenaExprReturnsNilForInvalidID() {
        let arena = ASTArena()
        #expect(arena.expr(ExprID(rawValue: -1)) == nil)
        #expect(arena.expr(ExprID(rawValue: 0)) == nil)
        #expect(arena.expr(ExprID(rawValue: 999)) == nil)
    }

    @Test
    func testASTArenaExprSequentialIDs() {
        let r = makeRange(start: 0, end: 5)
        let arena = ASTArena()
        let id0 = arena.appendExpr(.intLiteral(1, r))
        let id1 = arena.appendExpr(.intLiteral(2, r))
        let id2 = arena.appendExpr(.intLiteral(3, r))
        #expect(id0.rawValue == 0)
        #expect(id1.rawValue == 1)
        #expect(id2.rawValue == 2)
    }

    @Test
    func testASTArenaExprWithMultipleTypes() {
        let interner = StringInterner()
        let r = makeRange(start: 0, end: 10)
        let arena = ASTArena()
        let intID = arena.appendExpr(.intLiteral(1, r))
        let boolID = arena.appendExpr(.boolLiteral(false, r))
        let strID = arena.appendExpr(.stringLiteral(interner.intern("test"), r))
        let breakID = arena.appendExpr(.breakExpr(range: r))

        if case .intLiteral = arena.expr(intID) {} else { Issue.record("Expected .intLiteral") }
        if case .boolLiteral = arena.expr(boolID) {} else { Issue.record("Expected .boolLiteral") }
        if case .stringLiteral = arena.expr(strID) {} else { Issue.record("Expected .stringLiteral") }
        if case .breakExpr = arena.expr(breakID) {} else { Issue.record("Expected .breakExpr") }
    }
}
#endif
