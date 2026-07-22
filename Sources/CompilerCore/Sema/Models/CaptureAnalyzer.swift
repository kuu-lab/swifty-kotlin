
struct CaptureAnalyzer {
    /// Same traversal as `collectCapturedOuterSymbols(in:...)`, but rooted at a
    /// function body (used for object-literal member functions, which have a
    /// `FunctionBody` rather than a single root `ExprID`). Each top-level
    /// statement is visited independently and the resulting capture sets are
    /// unioned, which is equivalent to visiting the whole body in one pass
    /// since the visitor carries no cross-statement state besides the
    /// accumulated capture set itself.
    func collectCapturedOuterSymbols(
        inBody body: FunctionBody,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }
        let roots: [ExprID] = switch body {
        case let .block(exprs, _): exprs
        case let .expr(expr, _): [expr]
        case .unit: []
        }
        var captured: Set<SymbolID> = []
        for root in roots {
            captured.formUnion(collectCapturedOuterSymbols(
                in: root,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols,
                skipNestedClosures: skipNestedClosures
            ))
        }
        return captured.sorted(by: { $0.rawValue < $1.rawValue })
    }

    func collectCapturedOuterSymbols(
        in exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        outerSymbols: Set<SymbolID>,
        skipNestedClosures: Bool = true
    ) -> [SymbolID] {
        guard !outerSymbols.isEmpty else {
            return []
        }

        var captured: Set<SymbolID> = []

        func recordCapture(for targetExprID: ExprID) {
            guard let symbol = sema.bindings.identifierSymbol(for: targetExprID),
                  outerSymbols.contains(symbol)
            else {
                return
            }
            captured.insert(symbol)
        }

        func visitBody(_ body: FunctionBody) {
            switch body {
            case let .block(exprs, _):
                for expr in exprs {
                    visit(expr)
                }
            case let .expr(expr, _):
                visit(expr)
            case .unit:
                break
            }
        }

        // swiftlint:disable:next cyclomatic_complexity
        func visit(_ currentExprID: ExprID) {
            guard let expr = ast.arena.expr(currentExprID) else {
                return
            }
            switch expr {
            case .nameRef:
                recordCapture(for: currentExprID)

            case let .forExpr(_, iterable, body, _, _):
                visit(iterable)
                visit(body)

            case let .whileExpr(condition, body, _, _):
                visit(condition)
                visit(body)

            case let .doWhileExpr(body, condition, _, _):
                visit(body)
                visit(condition)

            case let .localDecl(_, _, _, initializer, _, _):
                if let initializer {
                    visit(initializer)
                }

            case let .localAssign(_, value, _):
                visit(value)

            case let .memberAssign(receiver, _, value, _):
                visit(receiver)
                visit(value)

            case let .indexedAssign(receiver, indices, value, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }
                visit(value)

            case let .call(callee, _, args, _):
                visit(callee)
                for arg in args {
                    visit(arg.expr)
                }

            case let .memberCall(receiver, _, _, args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case let .indexedAccess(receiver, indices, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }

            case let .binary(_, lhs, rhs, _):
                visit(lhs)
                visit(rhs)

            case let .whenExpr(subject, branches, elseExpr, _):
                if let subject {
                    visit(subject)
                }
                for branch in branches {
                    for condition in branch.conditions {
                        visit(condition)
                    }
                    if let guardExpr = branch.guard_ {
                        visit(guardExpr)
                    }
                    visit(branch.body)
                }
                if let elseExpr {
                    visit(elseExpr)
                }

            case let .returnExpr(value, _, _):
                if let value {
                    visit(value)
                }

            case let .ifExpr(condition, thenExpr, elseExpr, _):
                visit(condition)
                visit(thenExpr)
                if let elseExpr {
                    visit(elseExpr)
                }

            case let .tryExpr(body, catchClauses, finallyExpr, _):
                visit(body)
                for catchClause in catchClauses {
                    visit(catchClause.body)
                }
                if let finallyExpr {
                    visit(finallyExpr)
                }

            case let .unaryExpr(_, operand, _):
                visit(operand)

            case let .isCheck(value, _, _, _):
                visit(value)

            case let .asCast(value, _, _, _):
                visit(value)

            case let .nullAssert(value, _):
                visit(value)

            case let .safeMemberCall(receiver, _, _, args, _):
                visit(receiver)
                for arg in args {
                    visit(arg.expr)
                }

            case let .compoundAssign(_, _, value, _):
                recordCapture(for: currentExprID)
                visit(value)

            case let .indexedCompoundAssign(_, receiver, indices, value, _):
                visit(receiver)
                for idx in indices {
                    visit(idx)
                }
                visit(value)

            case let .memberCompoundAssign(_, receiver, _, value, _):
                visit(receiver)
                visit(value)

            case let .throwExpr(value, _):
                visit(value)

            case let .lambdaLiteral(_, body, _, _):
                if !skipNestedClosures {
                    visit(body)
                }

            case let .callableRef(receiver, _, _):
                if let receiver {
                    visit(receiver)
                }

            case let .localFunDecl(_, _, _, body, _, _):
                if !skipNestedClosures {
                    visitBody(body)
                }

            case let .blockExpr(statements, trailingExpr, _):
                for statement in statements {
                    visit(statement)
                }
                if let trailingExpr {
                    visit(trailingExpr)
                }

            case let .stringTemplate(parts, _):
                for part in parts {
                    if case let .expression(expr) = part {
                        visit(expr)
                    }
                }

            case let .inExpr(lhs, rhs, _),
                 let .notInExpr(lhs, rhs, _):
                visit(lhs)
                visit(rhs)

            case let .destructuringDecl(_, _, initializer, _):
                visit(initializer)

            case let .forDestructuringExpr(_, iterable, body, _):
                visit(iterable)
                visit(body)

            case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
                 .charLiteral, .boolLiteral, .stringLiteral,
                 .breakExpr, .continueExpr, .objectLiteral, .superRef, .thisRef:
                break
            }
        }

        visit(exprID)
        return captured.sorted(by: { $0.rawValue < $1.rawValue })
    }
}
