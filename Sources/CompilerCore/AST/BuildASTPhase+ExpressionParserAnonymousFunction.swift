
extension BuildASTPhase.ExpressionParser {
    /// Parses an anonymous function expression: `fun(params): RetType { body }`.
    ///
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
    /// Only the block-body form is handled here. An expression-body
    /// anonymous function (`fun(x) = x * 2`) and a receiver form
    /// (`fun Int.(x) { ... }`) are not parsed by this method and fall
    /// through to `parsePrimary`'s ordinary keyword handling — see
    /// KUU-BUG-B-EXPR-BODY for the deferred follow-up.
    func parseAnonymousFunctionLiteral() -> ExprID? {
        guard let funToken = current(), case .keyword(.fun) = funToken.kind else {
            return nil
        }
        guard peek(1)?.kind == .symbol(.lParen) else {
            return nil
        }

        let startIndex = index
        _ = consume() // `fun`
        skipBalancedParenthesisIfNeeded() // value-parameter list

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

        guard matches(.symbol(.lBrace)) else {
            index = startIndex
            return nil
        }
        skipBalancedBraceIfNeeded()
        let endIndex = index

        let syntheticName = interner.intern(
            "__AnonymousFunction_\(funToken.range.start.file.rawValue)_\(funToken.range.start.offset)"
        )
        let nameToken = Token(kind: .identifier(syntheticName), range: funToken.range)
        var synthTokens: [Token] = [funToken, nameToken]
        synthTokens.append(contentsOf: tokens[(startIndex + 1)..<endIndex])

        let phase = BuildASTPhase(diagnostics: diagnostics)
        guard let localFunExprID = phase.parseLocalFunDeclExpr(
            from: synthTokens, interner: interner, astArena: astArena
        ) else {
            index = startIndex
            return nil
        }

        let range = SourceRange(start: funToken.range.start, end: tokens[endIndex - 1].range.end)
        let callableRefID = astArena.appendExpr(.callableRef(receiver: nil, member: syntheticName, range: range))
        return astArena.appendExpr(.blockExpr(statements: [localFunExprID], trailingExpr: callableRefID, range: range))
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
