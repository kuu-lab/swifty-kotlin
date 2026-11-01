/// The alias map itself (`expandInlineCalls`'s `aliases`,
/// `expandInlineCall`/`expandLambdaBody`'s `localExprMap`) stays owned by the
/// caller: those functions also write bindings directly for cases that are
/// not themselves a resolution concern (parameter substitution, merge-slot
/// promotion), so this type only owns the read side and the one instruction
/// rewrite built from it.
enum InlineExprAliasing {
    /// Stops at a self-alias, or once revisiting an already-seen expression
    /// would loop forever, so a cycle resolves to the last expression reached
    /// instead of hanging.
    static func resolveAlias(of expr: KIRExprID, aliases: [KIRExprID: KIRExprID]) -> KIRExprID {
        var current = expr
        var visited: Set<KIRExprID> = []
        var hops = 0
        while let next = aliases[current], next != current {
            hops += 1
            if hops == 2 {
                // A revisit is only possible from the third hop onward
                // (`next != current` already covers self-aliases, and the
                // second hop cannot revisit `expr`), so the visited set is
                // seeded here rather than allocated on the common
                // single-hop resolution.
                visited = [expr, current]
            } else if hops > 2 {
                guard visited.insert(current).inserted else { return current }
            }
            current = next
        }
        return current
    }

    /// Every defined result (`result:`, `thrownResult:`) is left as-is;
    /// `.copy` is the one case where both sides -- `from` and its own `to` --
    /// are resolved.
    static func rewriteInstruction(_ instruction: KIRInstruction, aliases: [KIRExprID: KIRExprID]) -> KIRInstruction {
        // `expandInlineCalls` rewrites the whole caller body every round but
        // only populates its alias map during lambda splices — most rounds it
        // stays empty, so resolving is identity and the rebuilt instruction
        // (plus a fresh `arguments` array per call) is pure allocation.
        guard !aliases.isEmpty else { return instruction }
        return switch instruction {
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

        case let .nonLocalReturn(value, target):
            .nonLocalReturn(value.map { resolveAlias(of: $0, aliases: aliases) }, target: target)

        case let .beginNonLocalReturnScope(value, target, function):
            .beginNonLocalReturnScope(value: resolveAlias(of: value, aliases: aliases), target: target, function: function)

        case let .resumeNonLocalReturn(value):
            .resumeNonLocalReturn(resolveAlias(of: value, aliases: aliases))

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

    /// Used to invalidate a stale alias binding once its key is legitimately
    /// redefined by a later instruction. Deliberately narrower than
    /// `KIRVerifier`'s full def tracking (`InlineDefinedExprIndex`): a
    /// `.copy`'s `to` and a call's `thrownResult` are not counted as
    /// definitions here.
    static func definedResult(in instruction: KIRInstruction) -> KIRExprID? {
        switch instruction {
        case let .constValue(result, _),
             let .binary(_, _, _, result),
             let .unary(_, _, result),
             let .nullAssert(_, result),
             let .loadGlobal(result, _):
            result
        case let .call(_, _, _, result, _, _, _, _), let .virtualCall(_, _, _, _, result, _, _, _):
            result
        default:
            nil
        }
    }
}
