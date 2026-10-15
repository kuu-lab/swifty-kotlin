
extension BuildASTPhase.ExpressionParser {
    func hasContextParameterAnonymousFunctionPrefix() -> Bool {
        guard index + 1 < tokens.count,
              tokens[index].kind == .softKeyword(.context),
              tokens[index + 1].kind == .symbol(.lParen)
        else {
            return false
        }
        var depth = 0
        var cursor = index + 1
        while cursor < tokens.count {
            switch tokens[cursor].kind {
            case .symbol(.lParen): depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0 {
                    cursor += 1
                    while cursor < tokens.count,
                          case let .keyword(keyword) = tokens[cursor].kind,
                          KotlinParser.isDeclarationModifierKeyword(keyword)
                    {
                        cursor += 1
                    }
                    return cursor + 1 < tokens.count
                        && tokens[cursor].kind == .keyword(.fun)
                        && tokens[cursor + 1].kind == .symbol(.lParen)
                }
            default: break
            }
            cursor += 1
        }
        return false
    }

    /// Unlike a lambda literal, an unlabeled `return` inside an anonymous
    /// function always returns from the anonymous function itself — never a
    /// non-local return to an enclosing named function — regardless of
    /// whether the anonymous function ends up inlined into a higher-order
    /// call. `.localFunDecl` already gets this right (its own Sema/KIR
    /// lowering resets the return target to itself), so this desugars to a
    /// synthetic local function declaration plus a bound callable reference
    /// to it, wrapped in a block so the synthetic name's scope doesn't leak
    /// into the surrounding expression:
    ///
    ///     fun(x: Int): Int { return x * 2 }
    ///     // desugars to (with a fresh, unspellable synthetic name):
    ///     { fun __AnonymousFunction_7_142(x: Int): Int { return x * 2 }; ::__AnonymousFunction_7_142 }
    ///
    /// Both block and expression bodies reuse local-function semantics.
    ///
    /// A `label@ fun(...)` prefix reuses the label as the synthetic function
    /// name so `return@label` resolves like a function-name labeled return.
    func parseAnonymousFunctionLiteral(label: InternedString? = nil) -> ExprID? {
        let expressionStartIndex = index
        var functionStartIndex = index
        if hasContextParameterAnonymousFunctionPrefix() {
            var depth = 0
            var cursor = index + 1
            while cursor < tokens.count {
                switch tokens[cursor].kind {
                case .symbol(.lParen): depth += 1
                case .symbol(.rParen):
                    depth -= 1
                    if depth == 0 {
                        functionStartIndex = cursor + 1
                        while functionStartIndex < tokens.count,
                              case let .keyword(keyword) = tokens[functionStartIndex].kind,
                              KotlinParser.isDeclarationModifierKeyword(keyword)
                        {
                            functionStartIndex += 1
                        }
                        break
                    }
                default: break
                }
                if functionStartIndex != index { break }
                cursor += 1
            }
        }
        guard functionStartIndex < tokens.count,
              case .keyword(.fun) = tokens[functionStartIndex].kind
        else {
            return nil
        }
        guard tokens.indices.contains(functionStartIndex + 1),
              tokens[functionStartIndex + 1].kind == .symbol(.lParen)
        else {
            return nil
        }

        index = functionStartIndex
        let startIndex = functionStartIndex
        let funToken = tokens[functionStartIndex]
        _ = consume()
        skipBalancedParenthesisIfNeeded()

        if matches(.symbol(.colon)) {
            _ = consume()
            var depth = BuildASTPhase.BracketDepth()
            while let token = current() {
                if depth.isAtTopLevel, token.kind == .symbol(.lBrace) || token.kind == .symbol(.assign) {
                    break
                }
                depth.track(token.kind)
                _ = consume()
            }
        }

        let expressionBody: ExprID?
        let headerEndIndex = index
        if matches(.symbol(.assign)) {
            _ = consume()
            guard let body = parseExpression(minPrecedence: 0) else {
                index = expressionStartIndex
                return nil
            }
            expressionBody = body
        } else if matches(.symbol(.lBrace)) {
            skipBalancedBraceIfNeeded()
            expressionBody = nil
        } else {
            index = expressionStartIndex
            return nil
        }
        let endIndex = index

        let syntheticName = label ?? interner.intern(
            "__AnonymousFunction_\(funToken.range.start.file.rawValue)_\(funToken.range.start.offset)"
        )
        let nameToken = Token(kind: .identifier(syntheticName), range: funToken.range)
        var synthTokens = Array(tokens[expressionStartIndex..<functionStartIndex])
        synthTokens.append(contentsOf: [funToken, nameToken])
        synthTokens.append(contentsOf: tokens[(startIndex + 1)..<(expressionBody == nil ? endIndex : headerEndIndex)])

        let phase = BuildASTPhase(diagnostics: diagnostics)
        guard let localFunExprID = phase.parseLocalFunDeclExpr(
            from: synthTokens, interner: interner, astArena: astArena,
            bodyOverride: expressionBody.flatMap { body in
                astArena.exprRange(body).map { .expr(body, $0) }
            }
        ) else {
            index = expressionStartIndex
            return nil
        }

        let range = SourceRange(start: tokens[expressionStartIndex].range.start, end: tokens[endIndex - 1].range.end)
        let callableRefID = astArena.appendExpr(.callableRef(receiver: nil, member: syntheticName, range: range))
        let function = astArena.appendExpr(.blockExpr(statements: [localFunExprID], trailingExpr: callableRefID, range: range))
        astArena.markAnonymousFunction(function)
        return function
    }

    private func skipBalancedBraceIfNeeded() {
        guard matches(.symbol(.lBrace)) else {
            return
        }
        _ = consume()
        var depth = 1
        while let token = current(), depth > 0 {
            _ = consume()
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
            default:
                continue
            }
        }
    }
}
