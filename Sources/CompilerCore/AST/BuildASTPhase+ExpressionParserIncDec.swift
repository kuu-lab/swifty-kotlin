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
    /// Postfix name and member mutations cache the loaded value so a property
    /// getter runs once.
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

    func tryParsePrefixIncrementDecrement() -> ExprID? {
        guard let opToken = current(), let op = compoundAssignOp(for: opToken.kind) else {
            return nil
        }
        let savedIndex = index
        _ = consume()
        guard let operand = parsePrefixUnary(),
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
        let annotations = astArena.expressionAnnotations(for: operand)
        let range = SourceRange(
            start: isPrefix ? opRange.start : operandRange.start,
            end: isPrefix ? operandRange.end : opRange.end
        )

        let readExpr: ExprID
        let assignExpr: ExprID
        var statements: [ExprID] = []
        switch operandExpr {
        case let .nameRef(name, _):
            readExpr = astArena.appendExpr(.nameRef(name, operandRange))
            let one = astArena.appendExpr(.intLiteral(1, opRange))
            let assignment = astArena.appendExpr(.compoundAssign(
                op: op,
                name: name,
                value: one,
                range: operandRange
            ))
            astArena.markIncrementDecrement(assignment, returnsValue: isPrefix)
            assignExpr = assignment

        case let .memberCall(receiver, callee, typeArgs, args, _)
            where typeArgs.isEmpty && args.isEmpty:
            // A name reference can still invoke a top-level property's getter.
            // Capture every receiver once because the synthesized read and
            // write otherwise evaluate that reference separately.
            let receiverRange = astArena.exprRange(receiver) ?? operandRange
            let receiverName = interner.intern("$incdec$receiver$\(nextIncDecTempID())")
            statements.append(astArena.appendExpr(.localDecl(
                name: receiverName,
                isMutable: false,
                typeAnnotation: nil,
                initializer: receiver,
                range: receiverRange
            )))
            let cachedReceiver = astArena.appendExpr(.nameRef(receiverName, receiverRange))
            readExpr = astArena.appendExpr(.memberCall(
                receiver: cachedReceiver,
                callee: callee,
                typeArgs: [],
                args: [],
                range: operandRange
            ))
            let one = astArena.appendExpr(.intLiteral(1, opRange))
            let assignment = astArena.appendExpr(.memberCompoundAssign(
                op: op,
                receiver: cachedReceiver,
                callee: callee,
                value: one,
                // This synthetic mutation and its read represent one property
                // use. Share the operand range so annotation diagnostics dedup.
                range: operandRange
            ))
            astArena.markIncrementDecrement(assignment, returnsValue: isPrefix)
            assignExpr = assignment

        case let .indexedAccess(receiver, indices, _):
            return desugarIndexedIncrementDecrement(
                receiver: receiver, indices: indices, op: op,
                operandRange: operandRange, range: range, isPrefix: isPrefix,
                annotations: annotations
            )

        default:
            // Unsupported target: leave the operator unparsed so
            // the existing behaviour is preserved.
            return nil
        }

        if !annotations.isEmpty {
            astArena.prependExpressionAnnotations(annotations, for: readExpr)
        }

        if isPrefix {
            // Prefix mutation evaluates the property again after the setter.
            // This preserves observable custom getter behavior and returns a
            // setter-normalized value, matching Kotlin's `{ x += 1; x }`.
            // The re-read is stored in a fresh immutable local so the block
            // yields a snapshot register (KUU-4038): a bare `x` trailing read
            // returns the variable's own storage cell, so `val p = ++x` and
            // `++x + ++x` would alias it and observe later writes.
            astArena.markIncrementDecrement(assignExpr, cachedValue: readExpr)
            let resultName = makeTempName(range)
            let resultDecl = astArena.appendExpr(.localDecl(
                name: resultName,
                isMutable: false,
                typeAnnotation: nil,
                initializer: readExpr,
                range: operandRange
            ))
            return astArena.appendExpr(.blockExpr(
                statements: statements + [assignExpr, resultDecl],
                trailingExpr: astArena.appendExpr(.nameRef(resultName, operandRange)),
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
        astArena.markIncrementDecrement(assignExpr, cachedValue: tempRef)
        return astArena.appendExpr(.blockExpr(
            statements: statements + [tempDecl, assignExpr],
            trailingExpr: tempRef,
            range: range
        ))
    }

    /// Kotlin evaluates the receiver and indices once, so non-trivial operands are hoisted into
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
        isPrefix: Bool,
        annotations: [AnnotationNode]
    ) -> ExprID {
        var statements: [ExprID] = []

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
        let read = {
            let expression = self.astArena.appendExpr(.indexedAccess(
                receiver: receiverRef(), indices: indexRefs.map { $0() }, range: operandRange
            ))
            if !annotations.isEmpty {
                self.astArena.prependExpressionAnnotations(annotations, for: expression)
            }
            return expression
        }
        let operatorName = interner.intern(op == .plusAssign ? "inc" : "dec")
        let applyOperator = { (operand: ExprID) in
            // The synthesized `inc()` / `dec()` call is an explicit invocation:
            // without the marker, zero-argument member syntax is checked as a
            // property access and rejected with SEMA-0309 ("inc() expected").
            let call = self.astArena.appendExpr(.memberCall(
                receiver: operand, callee: operatorName, typeArgs: [], args: [], range: range
            ))
            self.astArena.markExplicitCall(call)
            return call
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

    private func makeTempName(_ range: SourceRange) -> InternedString {
        interner.intern("$incdec$\(range.start.offset)$\(nextIncDecTempID())")
    }

}
