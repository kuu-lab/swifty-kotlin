/// Enumerates calls in result positions without crossing a new return scope or
/// a try region. Other expression children are still searched for explicit returns.
enum TailrecPositionWalker {
    static func visit(
        _ id: ExprID,
        in arena: ASTArena,
        isValuePosition: Bool,
        includeLabeledReturns: Bool = false,
        inlineLambdaArguments: Set<ExprID> = [],
        onCandidate: (ExprID) -> Void
    ) {
        guard let node = arena.expr(id) else { return }
        func child(_ id: ExprID, result: Bool = false) {
            visit(id, in: arena, isValuePosition: result,
                  includeLabeledReturns: includeLabeledReturns,
                  inlineLambdaArguments: inlineLambdaArguments,
                  onCandidate: onCandidate)
        }
        switch node {
        case let .returnExpr(value, label, _):
            if label == nil || includeLabeledReturns, let value { child(value, result: true) }
        case let .call(callee, _, args, _):
            if isValuePosition { onCandidate(id) }
            child(callee)
            for argument in args {
                if inlineLambdaArguments.contains(argument.expr),
                   case let .lambdaLiteral(_, body, _, _)? = arena.expr(argument.expr)
                {
                    child(body)
                } else {
                    child(argument.expr)
                }
            }
        case let .memberCall(receiver, _, _, args, _), let .safeMemberCall(receiver, _, _, args, _):
            if isValuePosition { onCandidate(id) }
            child(receiver)
            for argument in args {
                if inlineLambdaArguments.contains(argument.expr),
                   case let .lambdaLiteral(_, body, _, _)? = arena.expr(argument.expr)
                {
                    child(body)
                } else {
                    child(argument.expr)
                }
            }
        case let .ifExpr(condition, yes, no, _):
            child(condition)
            child(yes, result: isValuePosition)
            if let no { child(no, result: isValuePosition) }
        case let .whenExpr(subject, branches, fallback, _):
            if let subject { child(subject) }
            for branch in branches {
                for condition in branch.conditions { child(condition) }
                if let guard_ = branch.guard_ { child(guard_) }
                child(branch.body, result: isValuePosition)
            }
            if let fallback { child(fallback, result: isValuePosition) }
        case let .blockExpr(statements, trailing, _):
            for statement in statements { child(statement) }
            if let trailing { child(trailing, result: isValuePosition) }
        case let .binary(op, lhs, rhs, _):
            child(lhs)
            child(rhs, result: op == .elvis && isValuePosition)
        case let .whileExpr(condition, body, _, _), let .doWhileExpr(body, condition, _, _):
            child(condition)
            child(body)
        case let .forExpr(_, _, iterable, body, _, _), let .forDestructuringExpr(_, iterable, body, _, _):
            child(iterable)
            child(body)
        case let .localDecl(_, _, _, initializer, _, _, _):
            if let initializer { child(initializer) }
        case let .destructuringDecl(_, _, initializer, _):
            child(initializer)
        case let .localAssign(_, value, _), let .compoundAssign(_, _, value, _),
             let .throwExpr(value, _), let .unaryExpr(_, value, _),
             let .isCheck(value, _, _, _), let .asCast(value, _, _, _), let .nullAssert(value, _):
            child(value)
        case let .memberAssign(receiver, _, value, _), let .safeMemberAssign(receiver, _, value, _),
             let .memberCompoundAssign(_, receiver, _, value, _):
            child(receiver)
            child(value)
        case let .indexedAssign(receiver, indices, value, _),
             let .indexedCompoundAssign(_, receiver, indices, value, _):
            child(receiver)
            for index in indices { child(index) }
            child(value)
        case let .indexedAccess(receiver, indices, _):
            child(receiver)
            for index in indices { child(index) }
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            child(lhs)
            child(rhs)
        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(value) = part { child(value) }
            }
        case let .callableRef(receiver, _, _):
            if let receiver { child(receiver) }
        case .lambdaLiteral, .localFunDecl, .localNominalDecl, .objectLiteral, .tryExpr:
            break
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral,
             .charLiteral, .nullLiteral, .boolLiteral, .stringLiteral, .nameRef,
             .breakExpr, .continueExpr, .superRef, .thisRef:
            break
        }
    }
}
