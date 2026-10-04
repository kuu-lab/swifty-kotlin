extension BuildASTPhase.ExpressionParser {
    /// Kotlin's `++` / `--` in *expression* position (`a[i++]`, `val x = i++`,
    /// `return i++`). Statement position is handled earlier by
    /// `parsePostfixMutation`, which never hands the operator token to the
    /// expression parser.
    ///
    /// Both forms are desugared into an already supported block expression so
    /// that no new AST node has to be threaded through Sema/KIR. The synthesized
    /// compound-assignment node is marked in the arena, which lets later phases
    /// distinguish `++` / `--` from source-written `+=` / `-=` and resolve the
    /// required `inc()` / `dec()` operator.
    ///
    ///   `x++`  ->  `{ val tmp = x; x += 1; tmp }`
    ///   `++x`  ->  `{ x += 1; x }`
    ///
    /// For a bare name the marked assignment reuses `.compoundAssign`, which
    /// already knows how to store back into locals, captured variables and
    /// globals after the operator result is computed. Member (`obj.p++`) and
    /// indexed (`a[i]++`) targets instead call `inc()` / `dec()` explicitly so
    /// that a custom getter / `get()` runs exactly once.
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
            let assignment = astArena.appendExpr(.compoundAssign(
                op: op,
                name: name,
                value: one,
                range: range
            ))
            astArena.markIncrementDecrement(assignment)
            assignExpr = assignment

        case let .memberCall(receiver, callee, typeArgs, args, _)
            where typeArgs.isEmpty && args.isEmpty:
            return desugarMemberIncrementDecrement(
                receiver: receiver,
                callee: callee,
                op: op,
                operandRange: operandRange,
                range: range,
                isPrefix: isPrefix
            )

        case let .indexedAccess(receiver, indices, _):
            return desugarIndexedIncrementDecrement(
                receiver: receiver,
                indices: indices,
                op: op,
                operandRange: operandRange,
                range: range,
                isPrefix: isPrefix
            )

        default:
            // Unsupported target: leave the operator unparsed so the existing
            // behaviour is preserved.
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

    /// `a[i]++` / `++a[i]` in expression position. Kotlin evaluates the
    /// receiver and indices once, so non-trivial operands are hoisted into
    /// temporaries and the element's `inc()` / `dec()` is called explicitly.
    /// Postfix reads the element once; prefix follows `a[i] = a[i].inc(); a[i]`
    /// and re-reads it after the write, exactly like kotlinc:
    ///
    ///   `a[i]++`  ->  `{ val r = a; val j = i; val old = r[j]; r[j] = old.inc(); old }`
    ///   `++a[i]`  ->  `{ val r = a; val j = i; r[j] = r[j].inc(); r[j] }`
    private func desugarIndexedIncrementDecrement(
        receiver: ExprID,
        indices: [ExprID],
        op: CompoundAssignOp,
        operandRange: SourceRange,
        range: SourceRange,
        isPrefix: Bool
    ) -> ExprID {
        var statements: [ExprID] = []

        // Returns a factory producing a fresh AST node that re-reads `expr`'s
        // value each time it is called.
        func stabilized(_ expr: ExprID) -> () -> ExprID {
            switch astArena.expr(expr) {
            case let .nameRef(name, nameRange):
                return { self.astArena.appendExpr(.nameRef(name, nameRange)) }
            case let .thisRef(label, thisRange):
                return { self.astArena.appendExpr(.thisRef(label: label, thisRange)) }
            case let .intLiteral(value, literalRange):
                return { self.astArena.appendExpr(.intLiteral(value, literalRange)) }
            default:
                let exprRange = astArena.exprRange(expr) ?? range
                let name = makeTempName(range)
                statements.append(astArena.appendExpr(.localDecl(
                    name: name, isMutable: false, typeAnnotation: nil, initializer: expr, range: exprRange
                )))
                return { self.astArena.appendExpr(.nameRef(name, exprRange)) }
            }
        }

        let receiverRef = stabilized(receiver)
        let indexRefs = indices.map(stabilized)
        let read = { self.astArena.appendExpr(.indexedAccess(
            receiver: receiverRef(), indices: indexRefs.map { $0() }, range: operandRange
        )) }
        let operatorName = interner.intern(op == .plusAssign ? "inc" : "dec")
        let applyOperator = { (operand: ExprID) in
            self.astArena.appendExpr(.memberCall(
                receiver: operand, callee: operatorName, typeArgs: [], args: [], range: range
            ))
        }

        if isPrefix {
            statements.append(astArena.appendExpr(.indexedAssign(
                receiver: receiverRef(), indices: indexRefs.map { $0() },
                value: applyOperator(read()), range: range
            )))
            return astArena.appendExpr(.blockExpr(
                statements: statements,
                trailingExpr: read(),
                range: range
            ))
        }
        let resultName = makeTempName(range)
        let resultRef = { self.astArena.appendExpr(.nameRef(resultName, operandRange)) }
        statements.append(astArena.appendExpr(.localDecl(
            name: resultName, isMutable: false, typeAnnotation: nil,
            initializer: read(), range: operandRange
        )))
        statements.append(astArena.appendExpr(.indexedAssign(
            receiver: receiverRef(), indices: indexRefs.map { $0() },
            value: applyOperator(resultRef()), range: range
        )))
        return astArena.appendExpr(.blockExpr(
            statements: statements,
            trailingExpr: resultRef(),
            range: range
        ))
    }

    /// `obj.p++` / `++obj.p` in expression position. Like the indexed form,
    /// a custom getter runs exactly as often as in kotlinc: postfix reads the
    /// property once into a temporary, prefix re-reads it after the write:
    ///
    ///   `obj.p++`  ->  `{ val old = obj.p; obj.p = old.inc(); old }`
    ///   `++obj.p`  ->  `{ obj.p = obj.p.inc(); obj.p }`
    ///
    /// Receivers with effects are evaluated once and cached before the property read.
    private func desugarMemberIncrementDecrement(
        receiver: ExprID,
        callee: InternedString,
        op: CompoundAssignOp,
        operandRange: SourceRange,
        range: SourceRange,
        isPrefix: Bool
    ) -> ExprID? {
        guard let receiverExpr = astArena.expr(receiver) else { return nil }
        var statements: [ExprID] = []
        let receiverRef: () -> ExprID
        if isSideEffectFreeReceiver(receiver) {
            receiverRef = { self.astArena.appendExpr(receiverExpr) }
        } else {
            let receiverRange = astArena.exprRange(receiver) ?? operandRange
            let receiverName = makeTempName(range)
            statements.append(astArena.appendExpr(.localDecl(
                name: receiverName, isMutable: false, typeAnnotation: nil,
                initializer: receiver, range: receiverRange
            )))
            receiverRef = { self.astArena.appendExpr(.nameRef(receiverName, receiverRange)) }
        }
        let read = { self.astArena.appendExpr(.memberCall(
            receiver: receiverRef(), callee: callee, typeArgs: [], args: [], range: operandRange
        )) }
        let operatorName = interner.intern(op == .plusAssign ? "inc" : "dec")
        let applyOperator = { (operand: ExprID) in
            self.astArena.appendExpr(.memberCall(
                receiver: operand, callee: operatorName, typeArgs: [], args: [], range: range
            ))
        }
        if isPrefix {
            let assignment = astArena.appendExpr(.memberAssign(
                receiver: receiverRef(), callee: callee, value: applyOperator(read()), range: range
            ))
            return astArena.appendExpr(.blockExpr(
                statements: statements + [assignment],
                trailingExpr: read(),
                range: range
            ))
        }
        let resultName = makeTempName(range)
        let resultRef = { self.astArena.appendExpr(.nameRef(resultName, operandRange)) }
        let resultDecl = astArena.appendExpr(.localDecl(
            name: resultName, isMutable: false, typeAnnotation: nil,
            initializer: read(), range: operandRange
        ))
        let assignment = astArena.appendExpr(.memberAssign(
            receiver: receiverRef(), callee: callee, value: applyOperator(resultRef()), range: range
        ))
        astArena.markIncrementDecrement(assignment, cachedValue: resultRef())
        return astArena.appendExpr(.blockExpr(
            statements: statements + [resultDecl, assignment],
            trailingExpr: resultRef(),
            range: range
        ))
    }

    private func makeTempName(_ range: SourceRange) -> InternedString {
        interner.intern("$incdec$\(range.start.offset)$\(nextIncDecTempID())")
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
