@testable import CompilerCore

enum GoldenHarnessExprFormat {
    static func renderExpr(_ expr: Expr, id: ExprID, ctx: StableRenderContext) -> String {
        let interner = ctx.interner
        switch expr {
        // Literals
        case let .intLiteral(value, _):
            return renderLiteral("int", value)
        case let .longLiteral(value, _):
            return renderLiteral("long", value)
        case let .uintLiteral(value, _):
            return renderLiteral("uint", value)
        case let .ulongLiteral(value, _):
            return renderLiteral("ulong", value)
        case let .floatLiteral(value, _):
            return renderLiteral("float", value)
        case let .doubleLiteral(value, _):
            return renderLiteral("double", value)
        case let .charLiteral(value, _):
            return renderLiteral("char", value)
        case let .boolLiteral(value, _):
            return "bool(\(value ? "true" : "false"))"
        case let .stringLiteral(text, _):
            return "string(\(interner.resolve(text)))"
        case let .nameRef(name, _):
            return "name(\(interner.resolve(name)))"

        // Control flow
        case let .forExpr(loopVariable, iterable, body, label, _):
            return renderLoopExpr("for", loopVariable, iterable, body, label, ctx,
                variableKey: "var", iterableKey: "iterable", bodyKey: "body")
        case let .whileExpr(condition, body, label, _):
            return renderWhileLoop(condition, body, label, ctx)
        case let .doWhileExpr(body, condition, label, _):
            return renderDoWhileLoop(body, condition, label, ctx)
        case let .breakExpr(label, _):
            return renderJumpExpr("break", label, ctx)
        case let .continueExpr(label, _):
            return renderJumpExpr("continue", label, ctx)

        // Declarations and assignments
        case let .localDecl(name, isMutable, typeAnnotation, initializer, isDelegated, _):
            return renderLocalDecl(name, isMutable, typeAnnotation, initializer, isDelegated, ctx)
        case let .localAssign(name, value, _):
            return "localAssign \(interner.resolve(name)) value=\(ctx.exprKey(value))"
        case let .indexedAssign(receiver, indices, value, _):
            let idxStr = indices.map { ctx.exprKey($0) }.joined(separator: ",")
            return "indexedAssign receiver=\(ctx.exprKey(receiver)) indices=[\(idxStr)] value=\(ctx.exprKey(value))"

        // Calls and member access
        case let .call(callee, _, args, _):
            return renderCall("call", callee: callee, args: args, ctx: ctx)
        case let .memberCall(receiver, callee, _, args, _):
            return renderMemberCall("memberCall", receiver: receiver, callee: callee, args: args, ctx: ctx)
        case let .safeMemberCall(receiver, callee, _, args, _):
            return renderMemberCall("safeMemberCall", receiver: receiver, callee: callee, args: args, ctx: ctx)
        case let .indexedAccess(receiver, indices, _):
            let idxStr = indices.map { ctx.exprKey($0) }.joined(separator: ",")
            return "indexedAccess receiver=\(ctx.exprKey(receiver)) indices=[\(idxStr)]"

        // Binary and unary operations
        case let .binary(oper, lhs, rhs, _):
            return "binary(\(oper)) lhs=\(ctx.exprKey(lhs)) rhs=\(ctx.exprKey(rhs))"
        case let .unaryExpr(oper, operand, _):
            return "unary(\(oper)) operand=\(ctx.exprKey(operand))"

        // Type operations
        case let .isCheck(expr, type, negated, _):
            let typeStr = ctx.sema.bindings.isCheckTargetTypes[id].map { ctx.renderType($0) } ?? ctx.renderTypeRef(type)
            return "isCheck\(negated ? "!" : "") expr=\(ctx.exprKey(expr)) type=\(typeStr)"
        case let .asCast(expr, type, isSafe, _):
            let typeStr = ctx.sema.bindings.castTargetTypes[id].map { ctx.renderType($0) } ?? ctx.renderTypeRef(type)
            return "asCast\(isSafe ? "?" : "") expr=\(ctx.exprKey(expr)) type=\(typeStr)"
        case let .nullAssert(expr, _):
            return "nullAssert expr=\(ctx.exprKey(expr))"

        // Control expressions
        case let .whenExpr(subject, branches, elseExpr, _):
            return renderWhenExpr(subject: subject, branches: branches, elseExpr: elseExpr, ctx: ctx)
        case let .returnExpr(value, label, _):
            let renderedValue = value.map { ctx.exprKey($0) } ?? "_"
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "return\(labelStr) value=\(renderedValue)"
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            let renderedElse = elseExpr.map { ctx.exprKey($0) } ?? "_"
            return "if cond=\(ctx.exprKey(condition)) then=\(ctx.exprKey(thenExpr)) else=\(renderedElse)"
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            let catches = catchClauses.map { ctx.exprKey($0.body) }.joined(separator: ",")
            let renderedFinally = finallyExpr.map { ctx.exprKey($0) } ?? "_"
            return "try body=\(ctx.exprKey(body)) catches=[\(catches)] finally=\(renderedFinally)"
        case let .compoundAssign(oper, name, value, _):
            return "compoundAssign(\(oper)) name=\(interner.resolve(name)) value=\(ctx.exprKey(value))"
        case let .indexedCompoundAssign(oper, receiver, indices, value, _):
            let idxStr = indices.map { ctx.exprKey($0) }.joined(separator: ",")
            let recv = "receiver=\(ctx.exprKey(receiver))"
            return "indexedCompoundAssign(\(oper)) \(recv) indices=[\(idxStr)] value=\(ctx.exprKey(value))"
        case let .stringTemplate(parts, _):
            let rendered = parts.map { part -> String in
                switch part {
                case let .literal(text):
                    return "lit(\(interner.resolve(text)))"
                case let .expression(exprID):
                    return "expr(\(ctx.exprKey(exprID)))"
                }
            }.joined(separator: ",")
            return "stringTemplate[\(rendered)]"
        case let .throwExpr(value, _):
            return "throw value=\(ctx.exprKey(value))"
        case let .lambdaLiteral(params, body, label, _):
            let renderedParams = params.map { interner.resolve($0) }.joined(separator: ",")
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "lambda params=[\(renderedParams)] body=\(ctx.exprKey(body))\(labelStr)"
        case let .objectLiteral(superTypes, _, _):
            let renderedSuperTypes = superTypes.map { ctx.renderTypeRef($0) }.joined(separator: ",")
            return "objectLiteral supers=[\(renderedSuperTypes)]"
        case let .callableRef(receiver, member, _):
            let renderedReceiver = receiver.map { ctx.exprKey($0) } ?? "_"
            return "callableRef recv=\(renderedReceiver) member=\(interner.resolve(member))"
        case let .localFunDecl(name, valueParams, returnType, body, isSuspend, _):
            let params = valueParams.map { interner.resolve($0.name) }.joined(separator: ",")
            let bodyStr = switch body {
            case let .block(exprs, _):
                "block[\(exprs.map { ctx.exprKey($0) }.joined(separator: ","))]"
            case let .expr(exprID, _):
                ctx.exprKey(exprID)
            case .unit:
                "unit"
            }
            let retStr = returnType.map { ctx.renderTypeRef($0) } ?? "nil"
            return "localFunDecl \(interner.resolve(name))\(isSuspend ? " suspend=1" : "") params=[\(params)] returnType=\(retStr) body=\(bodyStr)"
        case let .blockExpr(statements, trailingExpr, _):
            let stmts = statements.map { ctx.exprKey($0) }.joined(separator: ",")
            let trailing = trailingExpr.map { ctx.exprKey($0) } ?? "_"
            return "blockExpr stmts=[\(stmts)] trailing=\(trailing)"
        case let .superRef(qualifier, _):
            if let qualifier {
                return "super<\(interner.resolve(qualifier))>"
            }
            return "super"
        case let .thisRef(label, _):
            if let label {
                return "this@\(interner.resolve(label))"
            }
            return "this"
        case let .inExpr(lhs, rhs, _):
            return "inExpr lhs=\(ctx.exprKey(lhs)) rhs=\(ctx.exprKey(rhs))"
        case let .notInExpr(lhs, rhs, _):
            return "notInExpr lhs=\(ctx.exprKey(lhs)) rhs=\(ctx.exprKey(rhs))"
        case let .destructuringDecl(names, isMutable, initializer, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }
                .joined(separator: ",")
            let mutStr = "mutable=\(isMutable ? 1 : 0)"
            return "destructuringDecl names=[\(renderedNames)] \(mutStr) init=\(ctx.exprKey(initializer))"
        case let .forDestructuringExpr(names, iterable, body, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }
                .joined(separator: ",")
            return "forDestructuring names=[\(renderedNames)] iterable=\(ctx.exprKey(iterable)) body=\(ctx.exprKey(body))"
        case let .memberAssign(receiver, callee, value, _):
            return "memberAssign recv=\(ctx.exprKey(receiver)) callee=\(interner.resolve(callee)) value=\(ctx.exprKey(value))"
        case let .memberCompoundAssign(oper, receiver, callee, value, _):
            return "memberCompoundAssign(\(oper)) recv=\(ctx.exprKey(receiver)) callee=\(interner.resolve(callee)) value=\(ctx.exprKey(value))"
        }
    }

    // MARK: - Helper methods

    private static func renderLiteral<T>(_ type: String, _ value: T) -> String {
        return "\(type)(\(value))"
    }

    private static func renderLoopExpr(
        _ loopType: String,
        _ loopVariable: InternedString?,
        _ iterable: ExprID,
        _ body: ExprID,
        _ label: InternedString?,
        _ ctx: StableRenderContext,
        variableKey: String,
        iterableKey: String,
        bodyKey: String
    ) -> String {
        let variable = loopVariable.map { ctx.interner.resolve($0) } ?? "_"
        let labelStr = label.map { " label=\(ctx.interner.resolve($0))" } ?? ""
        return "\(loopType) \(variableKey)=\(variable) \(iterableKey)=\(ctx.exprKey(iterable)) \(bodyKey)=\(ctx.exprKey(body))\(labelStr)"
    }

    private static func renderWhileLoop(_ condition: ExprID, _ body: ExprID, _ label: InternedString?, _ ctx: StableRenderContext) -> String {
        let labelStr = label.map { " label=\(ctx.interner.resolve($0))" } ?? ""
        return "while cond=\(ctx.exprKey(condition)) body=\(ctx.exprKey(body))\(labelStr)"
    }

    private static func renderDoWhileLoop(_ body: ExprID, _ condition: ExprID, _ label: InternedString?, _ ctx: StableRenderContext) -> String {
        let labelStr = label.map { " label=\(ctx.interner.resolve($0))" } ?? ""
        return "doWhile body=\(ctx.exprKey(body)) cond=\(ctx.exprKey(condition))\(labelStr)"
    }

    private static func renderJumpExpr(_ jumpType: String, _ label: InternedString?, _ ctx: StableRenderContext) -> String {
        let labelStr = label.map { "@\(ctx.interner.resolve($0))" } ?? ""
        return "\(jumpType)\(labelStr)"
    }

    private static func renderLocalDecl(
        _ name: InternedString,
        _ isMutable: Bool,
        _ typeAnnotation: TypeRefID?,
        _ initializer: ExprID?,
        _ isDelegated: Bool,
        _ ctx: StableRenderContext
    ) -> String {
        let typeStr = typeAnnotation.map { ctx.renderTypeRef($0) } ?? "_"
        let initStr = initializer.map { ctx.exprKey($0) } ?? "_"
        let delegatedStr = isDelegated ? " delegated=1" : ""
        return "localDecl \(ctx.interner.resolve(name)) mutable=\(isMutable ? 1 : 0) type=\(typeStr) init=\(initStr)\(delegatedStr)"
    }

    private static func renderCall(_ callType: String, callee: ExprID, args: [CallArgument], ctx: StableRenderContext) -> String {
        let renderedArgs = args.map { arg in
            let label = arg.label.map { ctx.interner.resolve($0) } ?? "_"
            return "\(label):\(ctx.exprKey(arg.expr))"
        }.joined(separator: ",")
        return "\(callType) callee=\(ctx.exprKey(callee)) args=[\(renderedArgs)]"
    }

    private static func renderMemberCall(
        _ callType: String,
        receiver: ExprID,
        callee: InternedString,
        args: [CallArgument],
        ctx: StableRenderContext
    ) -> String {
        let renderedArgs = args.map { arg in
            let label = arg.label.map { ctx.interner.resolve($0) } ?? "_"
            return "\(label):\(ctx.exprKey(arg.expr))"
        }.joined(separator: ",")
        return "\(callType) recv=\(ctx.exprKey(receiver)) callee=\(ctx.interner.resolve(callee)) args=[\(renderedArgs)]"
    }

    private static func renderWhenExpr(
        subject: ExprID?,
        branches: [WhenBranch],
        elseExpr: ExprID?,
        ctx: StableRenderContext
    ) -> String {
        let renderedBranches = branches.map { branch in
            let conditions: String = if branch.conditions.isEmpty {
                "else"
            } else {
                branch.conditions.map { ctx.exprKey($0) }.joined(separator: ",")
            }
            let guardPart = branch.guard_.map { " if \(ctx.exprKey($0))" } ?? ""
            return "\(conditions)\(guardPart)->\(ctx.exprKey(branch.body))"
        }.joined(separator: ",")
        let renderedElse = elseExpr.map { ctx.exprKey($0) } ?? "_"
        let renderedSubject = subject.map { ctx.exprKey($0) } ?? "_"
        return "when subject=\(renderedSubject) branches=[\(renderedBranches)] else=\(renderedElse)"
    }
}
