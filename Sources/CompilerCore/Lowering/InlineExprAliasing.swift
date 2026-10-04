/// Resolves the alias chains inline expansion records when one expression
/// stands in for another -- a parameter bound to its argument, a call result
/// bound to an inlined lambda's return value, a branch-merge slot promoted to
/// a retyped replacement -- and applies that resolution across an
/// instruction's read operands.
///
/// The alias map itself (`expandInlineCalls`'s `aliases`,
/// `expandInlineCall`/`expandLambdaBody`'s `localExprMap`) stays owned by the
/// caller: those functions also write bindings directly for cases that are
/// not themselves a resolution concern (parameter substitution, merge-slot
/// promotion), so this type only owns the read side and the one instruction
/// rewrite built from it.
enum InlineExprAliasing {
    /// Follows `aliases` from `expr` to the value it ultimately stands for.
    /// Stops at a self-alias, or once revisiting an already-seen expression
    /// would loop forever, so a cycle resolves to the last expression reached
    /// instead of hanging.
    static func resolveAlias(of expr: KIRExprID, aliases: [KIRExprID: KIRExprID]) -> KIRExprID {
        var current = expr
        var visited: Set<KIRExprID> = []
        while let next = aliases[current], visited.insert(current).inserted {
            if next == current {
                break
            }
            current = next
        }
        return current
    }

    /// Rewrites the operands `instruction` reads through `aliases`, via
    /// `resolveAlias`. Every defined result (`result:`, `thrownResult:`) is
    /// left as-is; `.copy` is the one case where both sides -- `from` and its
    /// own `to` -- are resolved. Instruction kinds with no aliasable operand,
    /// including `.loadGlobal`, pass through unchanged.
    static func rewriteInstruction(_ instruction: KIRInstruction, aliases: [KIRExprID: KIRExprID]) -> KIRInstruction {
        switch instruction {
        case let .binary(op, lhs, rhs, result):
            .binary(
                op: op,
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                result: result
            )

        case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
            .call(
                symbol: symbol,
                callee: callee,
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                isSuperCall: isSuperCall,
                qualifiedSuperType: qualifiedSuperType
            )

        case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult, dispatch):
            .virtualCall(
                symbol: symbol,
                callee: callee,
                receiver: resolveAlias(of: receiver, aliases: aliases),
                arguments: arguments.map { resolveAlias(of: $0, aliases: aliases) },
                result: result,
                canThrow: canThrow,
                thrownResult: thrownResult,
                dispatch: dispatch
            )

        case let .returnValue(value):
            .returnValue(resolveAlias(of: value, aliases: aliases))

        case let .nonLocalReturn(value):
            .nonLocalReturn(value.map { resolveAlias(of: $0, aliases: aliases) })

        case let .returnIfEqual(lhs, rhs):
            .returnIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases)
            )

        case let .jumpIfEqual(lhs, rhs, target):
            .jumpIfEqual(
                lhs: resolveAlias(of: lhs, aliases: aliases),
                rhs: resolveAlias(of: rhs, aliases: aliases),
                target: target
            )

        case let .jumpIfNotNull(value, target):
            .jumpIfNotNull(
                value: resolveAlias(of: value, aliases: aliases),
                target: target
            )

        case let .copy(from, to):
            .copy(
                from: resolveAlias(of: from, aliases: aliases),
                to: resolveAlias(of: to, aliases: aliases)
            )

        case let .rethrow(value):
            .rethrow(value: resolveAlias(of: value, aliases: aliases))

        case let .unary(op, operand, result):
            .unary(
                op: op,
                operand: resolveAlias(of: operand, aliases: aliases),
                result: result
            )

        case let .nullAssert(operand, result):
            .nullAssert(
                operand: resolveAlias(of: operand, aliases: aliases),
                result: result
            )

        case let .storeGlobal(value, symbol):
            .storeGlobal(
                value: resolveAlias(of: value, aliases: aliases),
                symbol: symbol
            )

        case .loadGlobal:
            instruction

        default:
            instruction
        }
    }

    /// The expression `instruction` defines, if any. Used to invalidate a
    /// stale alias binding once its key is legitimately redefined by a later
    /// instruction. Deliberately narrower than `KIRVerifier`'s full def
    /// tracking (`exprIsDefined` in `InlineLoweringPass`): a `.copy`'s `to`
    /// and a call's `thrownResult` are not counted as definitions here.
    static func definedResult(in instruction: KIRInstruction) -> KIRExprID? {
        switch instruction {
        case let .constValue(result, _):
            result
        case let .binary(_, _, _, result):
            result
        case let .call(_, _, _, result, _, _, _, _):
            result
        case let .virtualCall(_, _, _, _, result, _, _, _):
            result
        case let .unary(_, _, result):
            result
        case let .nullAssert(_, result):
            result
        case let .loadGlobal(result, _):
            result
        default:
            nil
        }
    }
}
