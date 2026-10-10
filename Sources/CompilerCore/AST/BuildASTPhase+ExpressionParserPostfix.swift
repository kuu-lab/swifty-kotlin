
extension BuildASTPhase.ExpressionParser {
    /// Kotlin spec: lambdas get the callee name as their implicit label for
    /// `return@label`.
    private func calleeNameForImplicitLabel(_ exprID: ExprID) -> InternedString? {
        guard let expr = astArena.expr(exprID) else { return nil }
        switch expr {
        case let .nameRef(name, _):
            return name
        case let .memberCall(_, callee, _, _, _):
            return callee
        default:
            return nil
        }
    }

    private func parseLabeledTrailingLambda() -> ExprID? {
        guard let nameToken = current(),
              let name = labelNameFromToken(nameToken),
              let atToken = peek(1), atToken.kind == .symbol(.at),
              let braceToken = peek(2), braceToken.kind == .symbol(.lBrace)
        else {
            return nil
        }
        let savedIndex = index
        _ = consume()
        _ = consume()
        if let lambda = parseLambdaLiteral(label: name, start: nameToken.range.start) {
            return lambda
        }
        index = savedIndex
        return nil
    }

    private func parseTrailingLambda(implicitLabel: InternedString?) -> ExprID? {
        if matches(.symbol(.lBrace)) {
            return parseLambdaLiteral(label: implicitLabel)
        }
        return parseLabeledTrailingLambda()
    }

    func parsePostfixOrPrimary() -> ExprID? {
        let receiverStartIndex = index
        guard let expr = parsePrimary() else {
            return nil
        }
        return parsePostfixSuffixes(expr, receiverStartIndex: receiverStartIndex)
    }

    /// Call-argument lambdas re-enter here so that Kotlin's
    /// `{ ... }(...)` direct-invocation form parses: a `lambdaLiteral` is a
    /// `primaryExpression` and takes the same `postfixUnarySuffix` chain as
    /// any other primary.
    private func parsePostfixSuffixes(_ initialExpr: ExprID, receiverStartIndex: Int) -> ExprID {
        var expr = initialExpr
        while true {
            if matches(.symbol(.question)),
               let typeReceiver = tryParseCallableReferenceTypeReceiver(from: receiverStartIndex) {
                guard let reference = parseCallableReference(receiver: typeReceiver.expr, receiverTypeRef: typeReceiver.typeRef) else {
                    break
                }
                expr = reference
                continue
            }
            if matches(.symbol(.lessThan)) {
                if let typeReceiver = tryParseCallableReferenceTypeReceiver(from: receiverStartIndex) {
                    guard let reference = parseCallableReference(receiver: typeReceiver.expr, receiverTypeRef: typeReceiver.typeRef) else {
                        break
                    }
                    expr = reference
                    continue
                }
                let savedIndex = index
                if let typeArgs = tryParseExplicitTypeArgs() {
                    if matches(.symbol(.lParen)) {
                        guard let open = consume() else { break }
                        var args = parseCallArguments(implicitLambdaLabel: calleeNameForImplicitLabel(expr))
                        let close = consumeIf(.symbol(.rParen))
                        var callEndRange = close?.range ?? open.range
                        if let trailingLambda = parseTrailingLambda(implicitLabel: calleeNameForImplicitLabel(expr)) {
                            args.append(CallArgument(expr: trailingLambda))
                            callEndRange = astArena.exprRange(trailingLambda) ?? callEndRange
                        }
                        let fallbackEnd = close?.range.end ?? open.range.end
                        let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                        let range = mergeRanges(astArena.exprRange(expr), callEndRange, fallback: endRange)
                        expr = astArena.appendExpr(.call(callee: expr, typeArgs: typeArgs, args: args, range: range))
                        continue
                    }
                    if let trailingStart = current(),
                       let trailingLambda = parseTrailingLambda(implicitLabel: calleeNameForImplicitLabel(expr))
                    {
                        let trailingRange = astArena.exprRange(trailingLambda) ?? trailingStart.range
                        let range = mergeRanges(astArena.exprRange(expr), trailingRange, fallback: trailingRange)
                        expr = astArena.appendExpr(.call(
                            callee: expr,
                            typeArgs: typeArgs,
                            args: [CallArgument(expr: trailingLambda)],
                            range: range
                        ))
                        continue
                    }
                }
                index = savedIndex
            }

            if matches(.symbol(.lParen)) {
                guard let open = consume() else { break }
                var args = parseCallArguments(implicitLambdaLabel: calleeNameForImplicitLabel(expr))
                let close = consumeIf(.symbol(.rParen))
                var callEndRange = close?.range ?? open.range
                if let trailingLambda = parseTrailingLambda(implicitLabel: calleeNameForImplicitLabel(expr)) {
                    args.append(CallArgument(expr: trailingLambda))
                    callEndRange = astArena.exprRange(trailingLambda) ?? callEndRange
                }
                let fallbackEnd = close?.range.end ?? open.range.end
                let endRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
                let range = mergeRanges(astArena.exprRange(expr), callEndRange, fallback: endRange)
                expr = astArena.appendExpr(.call(callee: expr, typeArgs: [], args: args, range: range))
                continue
            }

            if let trailingStart = current(),
               let trailingLambda = parseTrailingLambda(implicitLabel: calleeNameForImplicitLabel(expr))
            {
                let trailingRange = astArena.exprRange(trailingLambda) ?? trailingStart.range
                let range = mergeRanges(astArena.exprRange(expr), trailingRange, fallback: trailingRange)
                expr = astArena.appendExpr(.call(
                    callee: expr,
                    typeArgs: [],
                    args: [CallArgument(expr: trailingLambda)],
                    range: range
                ))
                continue
            }

            if matches(.symbol(.lBracket)),
               let indexedExpr = tryParseIndexedAccess(receiver: expr)
            {
                expr = indexedExpr
                continue
            }

            if matches(.symbol(.plusPlus)) || matches(.symbol(.minusMinus)) {
                guard let mutation = tryParseIncrementDecrement(operand: expr) else {
                    break
                }
                expr = mutation
                continue
            }

            if matches(.symbol(.bangBang)) {
                guard let bangBang = consume() else { break }
                let range = mergeRanges(astArena.exprRange(expr), bangBang.range, fallback: bangBang.range)
                expr = astArena.appendExpr(.nullAssert(expr: expr, range: range))
                continue
            }

            if matches(.symbol(.doubleColon)) {
                guard let reference = parseCallableReference(receiver: expr) else {
                    break
                }
                expr = reference
                continue
            }

            let isSafeDot = matches(.symbol(.questionDot))
            let isDot = isSafeDot || matches(.symbol(.dot))
            guard isDot else {
                break
            }
            guard let dotToken = consume(),
                  let memberToken = consume(),
                  let memberName = tokenText(memberToken)
            else {
                break
            }
            var args: [CallArgument] = []
            var typeArgs: [TypeRefID] = []
            var memberEndRange = memberToken.range
            var hasExplicitCall = false
            if matches(.symbol(.lessThan)) {
                if let typeReceiver = tryParseCallableReferenceTypeReceiver(from: receiverStartIndex) {
                    guard let reference = parseCallableReference(receiver: typeReceiver.expr, receiverTypeRef: typeReceiver.typeRef) else {
                        break
                    }
                    expr = reference
                    continue
                }
                let savedIndex = index
                if let ta = tryParseExplicitTypeArgs() {
                    typeArgs = ta
                } else {
                    index = savedIndex
                }
            }
            if matches(.symbol(.lParen)),
               let open = consume()
            {
                hasExplicitCall = true
                args = parseCallArguments(implicitLambdaLabel: memberName)
                let close = consumeIf(.symbol(.rParen))
                memberEndRange = close?.range ?? open.range
            }
            if let trailingLambda = parseTrailingLambda(implicitLabel: memberName) {
                args.append(CallArgument(expr: trailingLambda))
                memberEndRange = astArena.exprRange(trailingLambda) ?? memberEndRange
            }
            let range = mergeRanges(astArena.exprRange(expr), memberEndRange, fallback: dotToken.range)
            if isSafeDot {
                let memberCall = astArena.appendExpr(.safeMemberCall(
                    receiver: expr,
                    callee: memberName,
                    typeArgs: typeArgs,
                    args: args,
                    range: range
                ))
                if hasExplicitCall {
                    astArena.markExplicitCall(memberCall)
                }
                expr = memberCall
            } else {
                let memberCall = astArena.appendExpr(.memberCall(
                    receiver: expr,
                    callee: memberName,
                    typeArgs: typeArgs,
                    args: args,
                    range: range
                ))
                if hasExplicitCall {
                    astArena.markExplicitCall(memberCall)
                }
                expr = memberCall
            }
        }
        return expr
    }

    private func tryParseIndexedAccess(receiver: ExprID) -> ExprID? {
        guard let open = consume() else { return nil }
        var indices: [ExprID] = []
        if !matches(.symbol(.rBracket)) {
            while true {
                guard let indexExpr = parseExpression(minPrecedence: 0) else { break }
                indices.append(indexExpr)
                if matches(.symbol(.comma)) {
                    _ = consume()
                    continue
                }
                break
            }
        }
        let close = consumeIf(.symbol(.rBracket))
        guard !indices.isEmpty else { return nil }
        let fallbackEnd = close?.range.end ?? open.range.end
        let fallbackRange = SourceRange(start: fallbackEnd, end: fallbackEnd)
        let range = mergeRanges(astArena.exprRange(receiver), close?.range ?? fallbackRange, fallback: open.range)
        return astArena.appendExpr(.indexedAccess(receiver: receiver, indices: indices, range: range))
    }

    func parseCallArguments(implicitLambdaLabel: InternedString? = nil) -> [CallArgument] {
        var args: [CallArgument] = []
        if !matches(.symbol(.rParen)) {
            while true {
                if let argument = parseCallArgument(implicitLambdaLabel: implicitLambdaLabel) {
                    args.append(argument)
                }
                if matches(.symbol(.comma)) {
                    _ = consume()
                    continue
                }
                if let unexpected = current(), unexpected.kind != .symbol(.rParen) {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0015",
                        "Expected ',' or ')' after call argument.",
                        range: unexpected.range
                    )
                }
                break
            }
        }
        return args
    }

    func parseCallArgument(implicitLambdaLabel: InternedString? = nil) -> CallArgument? {
        var isSpread = false
        var label: InternedString?
        if let first = current(),
           let second = peek(1),
           isArgumentLabelToken(first.kind),
           second.kind == .symbol(.assign)
        {
            label = tokenText(first)
            _ = consume()
            _ = consume()
        }

        // Kotlin places the spread operator after the optional argument label.
        if matches(.symbol(.star)) {
            _ = consume()
            isSpread = true
        }

        let expr: ExprID?
        if matches(.symbol(.lBrace)) {
            let lambdaStart = index
            if let lambda = parseLambdaLiteral(label: implicitLambdaLabel) {
                // A lambda literal is a primary expression: `foo({ 42 }())`
                // invokes the literal directly, and `foo({ 5 }() + { 6 }())`
                // continues into an infix expression — both postfix and infix
                // chains must keep going past the closing `}`.
                expr = parseInfixOperators(
                    lhs: parsePostfixSuffixes(lambda, receiverStartIndex: lambdaStart),
                    minPrecedence: 0
                )
            } else {
                expr = nil
            }
        } else if matches(.symbol(.lParen)) {
            let savedIndex = index
            _ = consume()
            if matches(.symbol(.lBrace)),
               let lambdaExpr = parseLambdaLiteral(label: implicitLambdaLabel),
               matches(.symbol(.rParen))
            {
                _ = consume()
                expr = parseInfixOperators(
                    lhs: parsePostfixSuffixes(lambdaExpr, receiverStartIndex: savedIndex),
                    minPrecedence: 0
                )
            } else {
                index = savedIndex
                expr = parseExpression(minPrecedence: 0)
            }
        } else {
            expr = parseExpression(minPrecedence: 0)
        }
        guard let expr else {
            return nil
        }
        return CallArgument(label: label, isSpread: isSpread, expr: expr)
    }

    func isArgumentLabelToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            true
        default:
            false
        }
    }

    func isPostfixSuffixStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.lParen), .symbol(.lBrace), .symbol(.lBracket),
             .symbol(.plusPlus), .symbol(.minusMinus), .symbol(.bangBang),
             .symbol(.doubleColon), .symbol(.dot), .symbol(.questionDot),
             .symbol(.lessThan):
            true
        default:
            false
        }
    }

    /// In Kotlin a `name@` label is a unary prefix on the whole postfix-unary
    /// expression, so `foo@{ ... }()` labels the invocation rather than the
    /// lambda literal. `return@foo` inside such a lambda resolves to a label
    /// that does not denote a function (kotlinc rejects it).
    func labeledLambdaBindsToPostfixExpression() -> Bool {
        var depth = 0
        var scan = index
        while scan < tokens.endIndex {
            switch tokens[scan].kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
            default:
                break
            }
            if depth == 0 {
                let next = scan + 1
                return next < tokens.endIndex && isPostfixSuffixStart(tokens[next].kind)
            }
            scan += 1
        }
        return false
    }
}
