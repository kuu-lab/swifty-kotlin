extension BuildASTPhase.ExpressionParser {
    /// Kotlin's `++` / `--` in *expression* position (`a[i++]`, `val x = i++`,
    /// `return i++`). Statement position is handled earlier by
    /// `parsePostfixMutation`, which never hands the operator token to the
    /// expression parser.
    ///
    /// Both forms are desugared into an already supported block expression so
    /// that no new AST node has to be threaded through Sema/KIR:
    ///
    ///   `x++`  ->  `{ val tmp = x; x += 1; tmp }`
    ///   `++x`  ->  `{ x += 1; x }`
    ///
    /// The augmented assignment reuses `.compoundAssign` / `.memberCompoundAssign`,
    /// which already know how to store back into locals, captured variables,
    /// globals and instance fields.
    func tryParseIncrementDecrement(operand: ExprID) -> ExprID? {
        guard let opToken = current(), let op = compoundAssignOp(for: opToken.kind) else {
            return nil
        }
        guard let desugared = desugarIncrementDecrement(
            operand: operand,
            op: op,
            opRange: opToken.range,
            isPrefix: false
        ) else {
            return nil
        }
        _ = consume()
        return desugared
    }

    /// Prefix `++x` / `--x`. Returns the value *after* the mutation.
    func tryParsePrefixIncrementDecrement() -> ExprID? {
        guard let opToken = current(), let op = compoundAssignOp(for: opToken.kind) else {
            return nil
        }
        let savedIndex = index
        _ = consume()
        guard let operand = parsePostfixOrPrimary(),
              let desugared = desugarIncrementDecrement(
                  operand: operand,
                  op: op,
                  opRange: opToken.range,
                  isPrefix: true
              )
        else {
            index = savedIndex
            return nil
        }
        return desugared
    }

    private func compoundAssignOp(for kind: TokenKind) -> CompoundAssignOp? {
        switch kind {
        case .symbol(.plusPlus): .plusAssign
        case .symbol(.minusMinus): .minusAssign
        default: nil
        }
    }

    private func desugarIncrementDecrement(
        operand: ExprID,
        op: CompoundAssignOp,
        opRange: SourceRange,
        isPrefix: Bool
    ) -> ExprID? {
        guard let operandExpr = astArena.expr(operand) else { return nil }
        let operandRange = astArena.exprRange(operand) ?? opRange
        let range = SourceRange(start: operandRange.start, end: opRange.end)

        // Builds a fresh read of the mutated storage plus the augmented
        // assignment that performs the mutation.
        let readExpr: ExprID
        let assignExpr: ExprID
        switch operandExpr {
        case let .nameRef(name, _):
            readExpr = astArena.appendExpr(.nameRef(name, operandRange))
            let one = astArena.appendExpr(.intLiteral(1, opRange))
            assignExpr = astArena.appendExpr(.compoundAssign(
                op: op,
                name: name,
                value: one,
                range: range
            ))

        case let .memberCall(receiver, callee, typeArgs, args, _)
            where typeArgs.isEmpty && args.isEmpty && isSideEffectFreeReceiver(receiver):
            readExpr = astArena.appendExpr(.memberCall(
                receiver: receiver,
                callee: callee,
                typeArgs: [],
                args: [],
                range: operandRange
            ))
            let one = astArena.appendExpr(.intLiteral(1, opRange))
            assignExpr = astArena.appendExpr(.memberCompoundAssign(
                op: op,
                receiver: receiver,
                callee: callee,
                value: one,
                range: range
            ))

        default:
            // Unsupported target (e.g. `a[i]++`): leave the operator unparsed so
            // the existing behaviour is preserved.
            return nil
        }

        if isPrefix {
            return astArena.appendExpr(.blockExpr(
                statements: [assignExpr],
                trailingExpr: readExpr,
                range: range
            ))
        }

        let tempName = interner.intern("$incdec$\(range.start.offset)$\(nextIncDecTempID())")
        let tempDecl = astArena.appendExpr(.localDecl(
            name: tempName,
            isMutable: false,
            typeAnnotation: nil,
            initializer: readExpr,
            range: operandRange
        ))
        let tempRef = astArena.appendExpr(.nameRef(tempName, operandRange))
        return astArena.appendExpr(.blockExpr(
            statements: [tempDecl, assignExpr],
            trailingExpr: tempRef,
            range: range
        ))
    }

    /// Only receivers that can be evaluated twice without observable effects are
    /// eligible, because the desugaring reads and writes the member separately.
    private func isSideEffectFreeReceiver(_ exprID: ExprID) -> Bool {
        switch astArena.expr(exprID) {
        case .nameRef, .thisRef:
            true
        default:
            false
        }
    }
}
