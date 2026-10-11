
extension CallTypeChecker {
    func lambdaBodyUsesImplicitIt(
        _ lambdaExprID: ExprID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(lambdaExprID) else {
            return false
        }
        var visited: Set<Int32> = []
        return expressionUsesImplicitIt(body, ctx: ctx, visited: &visited)
    }

    func lambdaBodyIsNullLiteral(
        _ lambdaExprID: ExprID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(lambdaExprID),
              case .nullLiteral = ctx.ast.arena.expr(body)
        else {
            return false
        }
        return true
    }

    // A no-arrow lambda only has an unresolvable implicit parameter when its
    // body actually references `it`; `{ null }` is a zero-parameter producer.
    private func expressionUsesImplicitIt(
        _ exprID: ExprID,
        ctx: TypeInferenceContext,
        visited: inout Set<Int32>
    ) -> Bool {
        guard visited.insert(exprID.rawValue).inserted,
              let expr = ctx.ast.arena.expr(exprID)
        else {
            return false
        }
        func visit(_ child: ExprID) -> Bool {
            return self.expressionUsesImplicitIt(child, ctx: ctx, visited: &visited)
        }
        switch expr {
        case let .nameRef(name, _):
            return name == ctx.interner.intern("it")
        case let .stringTemplate(parts, _):
            return parts.contains { part in
                if case let .expression(child) = part { return visit(child) }
                return false
            }
        case let .forExpr(_, iterable, body, _, _):
            return visit(iterable) || visit(body)
        case let .whileExpr(condition, body, _, _):
            return visit(condition) || visit(body)
        case let .doWhileExpr(body, condition, _, _):
            return visit(body) || visit(condition)
        case let .localDecl(_, _, _, initializer, _, _):
            return initializer.map(visit) ?? false
        case let .localAssign(_, value, _):
            return visit(value)
        case let .memberAssign(receiver, _, value, _):
            return visit(receiver) || visit(value)
        case let .indexedAssign(receiver, indices, value, _):
            return visit(receiver) || indices.contains(where: visit) || visit(value)
        case let .call(callee, _, args, _):
            return visit(callee) || args.contains { visit($0.expr) }
        case let .memberCall(receiver, _, _, args, _):
            return visit(receiver) || args.contains { visit($0.expr) }
        case let .indexedAccess(receiver, indices, _):
            return visit(receiver) || indices.contains(where: visit)
        case let .binary(_, lhs, rhs, _):
            return visit(lhs) || visit(rhs)
        case let .whenExpr(subject, branches, elseExpr, _):
            return (subject.map(visit) ?? false)
                || branches.contains { branch in
                    branch.conditions.contains(where: visit)
                        || (branch.guard_.map(visit) ?? false)
                        || visit(branch.body)
                }
                || (elseExpr.map(visit) ?? false)
        case let .returnExpr(value, _, _):
            return value.map(visit) ?? false
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return visit(condition) || visit(thenExpr) || (elseExpr.map(visit) ?? false)
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            return visit(body)
                || catchClauses.contains { visit($0.body) }
                || (finallyExpr.map(visit) ?? false)
        case let .unaryExpr(_, operand, _), let .nullAssert(operand, _):
            return visit(operand)
        case let .isCheck(value, _, _, _), let .asCast(value, _, _, _):
            return visit(value)
        case let .safeMemberCall(receiver, _, _, args, _):
            return visit(receiver) || args.contains { visit($0.expr) }
        case let .compoundAssign(_, _, value, _):
            return visit(value)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            return visit(receiver) || indices.contains(where: visit) || visit(value)
        case let .memberCompoundAssign(_, receiver, _, value, _):
            return visit(receiver) || visit(value)
        case let .throwExpr(value, _):
            return visit(value)
        case .lambdaLiteral, .localFunDecl:
            return false
        case let .callableRef(receiver, _, _):
            return receiver.map(visit) ?? false
        case let .blockExpr(statements, trailingExpr, _):
            return statements.contains(where: visit) || (trailingExpr.map(visit) ?? false)
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            return visit(lhs) || visit(rhs)
        case let .destructuringDecl(_, _, initializer, _):
            return visit(initializer)
        case let .forDestructuringExpr(_, iterable, body, _):
            return visit(iterable) || visit(body)
        case let .objectLiteral(_, declID, _):
            guard let declID,
                  let decl = ctx.ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl
            else {
                return false
            }
            return objectDecl.memberProperties.contains { propertyID in
                guard let property = ctx.ast.arena.decl(propertyID),
                      case let .propertyDecl(propertyDecl) = property,
                      let initializer = propertyDecl.initializer
                else { return false }
                return visit(initializer)
            }
        case let .localNominalDecl(declID, _):
            // KUU-555: an implicit `it` can only reach a local nominal through
            // expressions evaluated in the enclosing scope — supertype ctor
            // args for a local `object`, plus member property initializers
            // for both kinds.
            guard let decl = ctx.ast.arena.decl(declID) else {
                return false
            }
            let rootExprs: [ExprID]
            switch decl {
            case let .objectDecl(objectDecl):
                rootExprs = objectDecl.superTypeConstructorArgs.map(\.expr)
                    + objectDecl.memberProperties.compactMap { propertyID in
                        guard let property = ctx.ast.arena.decl(propertyID),
                              case let .propertyDecl(propertyDecl) = property
                        else { return nil }
                        return propertyDecl.initializer
                    }
            case let .classDecl(classDecl):
                rootExprs = classDecl.superTypeEntries
                    .flatMap(\.constructorArgs).map(\.expr)
                    + classDecl.memberProperties.compactMap { propertyID in
                        guard let property = ctx.ast.arena.decl(propertyID),
                              case let .propertyDecl(propertyDecl) = property
                        else { return nil }
                        return propertyDecl.initializer
                    }
            default:
                rootExprs = []
            }
            return rootExprs.contains(where: visit)
        case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral,
             .stringLiteral, .breakExpr, .continueExpr,
             .superRef, .thisRef:
            return false
        }
    }
}
