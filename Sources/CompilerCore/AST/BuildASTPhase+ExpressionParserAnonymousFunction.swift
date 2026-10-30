
extension BuildASTPhase.ExpressionParser {
    func isAnonymousFunctionLiteralStart(from offset: Int = 0) -> Bool {
        guard let token = peek(offset), token.kind == .keyword(.fun) else { return false }
        if let next = peek(offset + 1), next.kind == .symbol(.lParen) {
            return true
        }
        var cursor = offset + 1
        var depth = 0
        var prevNonTriviaKind: TokenKind? = nil
        while let tok = peek(cursor) {
            switch tok.kind {
            case .symbol(.lParen):
                if depth == 0 {
                    if let prev = prevNonTriviaKind {
                        switch prev {
                        case .keyword(.fun),
                             .symbol(.greaterThan),
                             .symbol(.dot),
                             .symbol(.questionDot):
                            return true
                        default:
                            return false
                        }
                    }
                    return false
                }
                depth += 1
            case .symbol(.rParen):
                depth -= 1
            case .symbol(.lBracket), .symbol(.lessThan):
                depth += 1
            case .symbol(.rBracket), .symbol(.greaterThan):
                depth -= 1
            case .symbol(.lBrace), .symbol(.rBrace), .symbol(.semicolon), .symbol(.assign):
                if depth == 0 { return false }
            default:
                break
            }
            prevNonTriviaKind = tok.kind
            cursor += 1
        }
        return false
    }

    func hasContextParameterAnonymousFunctionPrefix() -> Bool {
        guard index + 1 < tokens.endIndex,
              tokens[index].kind == .softKeyword(.context),
              tokens[index + 1].kind == .symbol(.lParen)
        else {
            return false
        }
        var depth = 0
        var cursor = index + 1
        while cursor < tokens.endIndex {
            switch tokens[cursor].kind {
            case .symbol(.lParen): depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0 {
                    cursor += 1
                    while cursor < tokens.endIndex,
                          case let .keyword(keyword) = tokens[cursor].kind,
                          KotlinParser.isDeclarationModifierKeyword(keyword)
                    {
                        cursor += 1
                    }
                    return isAnonymousFunctionLiteralStart(from: cursor - index)
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
    /// Block and plain expression bodies reuse local-function semantics.
    ///
    /// A `label@ fun(...)` prefix reuses the label as the synthetic function
    /// name so `return@label` resolves like a function-name labeled return.
    func parseAnonymousFunctionLiteral(label: InternedString? = nil) -> ExprID? {
        let expressionStartIndex = index
        var functionStartIndex = index
        if hasContextParameterAnonymousFunctionPrefix() {
            var depth = 0
            var cursor = index + 1
            while cursor < tokens.endIndex {
                switch tokens[cursor].kind {
                case .symbol(.lParen): depth += 1
                case .symbol(.rParen):
                    depth -= 1
                    if depth == 0 {
                        functionStartIndex = cursor + 1
                        while functionStartIndex < tokens.endIndex,
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
        guard functionStartIndex < tokens.endIndex,
              case .keyword(.fun) = tokens[functionStartIndex].kind
        else {
            return nil
        }
        guard isAnonymousFunctionLiteralStart(from: functionStartIndex - index) else {
            return nil
        }

        var lParenIndex: Int?
        var scanCursor = functionStartIndex + 1
        var scanDepth = 0
        while scanCursor < tokens.endIndex {
            let tok = tokens[scanCursor]
            switch tok.kind {
            case .symbol(.lParen):
                if scanDepth == 0 {
                    lParenIndex = scanCursor
                    break
                }
                scanDepth += 1
            case .symbol(.rParen):
                scanDepth -= 1
            case .symbol(.lBracket), .symbol(.lessThan):
                scanDepth += 1
            case .symbol(.rBracket), .symbol(.greaterThan):
                scanDepth -= 1
            case .symbol(.lBrace), .symbol(.rBrace), .symbol(.semicolon), .symbol(.assign):
                if scanDepth == 0 { break }
            default:
                break
            }
            if lParenIndex != nil { break }
            scanCursor += 1
        }
        guard let lParenIndex else {
            return nil
        }

        index = lParenIndex
        let funToken = tokens[functionStartIndex]
        // kotlinc reports 'type parameters are prohibited here' on generic
        // anonymous function literals — the `<` immediately after `fun`.
        if lParenIndex > functionStartIndex + 1,
           tokens[functionStartIndex + 1].kind == .symbol(.lessThan) {
            diagnostics?.error(
                "KSWIFTK-PARSE-0001",
                "type parameters are prohibited here.",
                range: tokens[functionStartIndex + 1].range
            )
        }
        skipBalancedParenthesisIfNeeded()

        if matches(.symbol(.colon)) {
            _ = consume()
            var depth = BuildASTPhase.BracketDepth()
            var previousKind: TokenKind?
            var sawAnnotation = false
            // The return type ends at `{`/`=` (body) or, for a bodiless
            // `fun(...): T`, at the enclosing boundary. Closers and
            // separators can't appear inside a type at top level, and a
            // second identifier can't extend a completed atom (`Int f`).
            typeScan: while let token = current() {
                if depth.isAtTopLevel {
                    switch token.kind {
                    case .symbol(.lBrace), .symbol(.assign),
                         .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace),
                         .symbol(.semicolon), .symbol(.comma), .eof:
                        break typeScan
                    case .identifier, .backtickedIdentifier, .softKeyword:
                        let followsAnnotationArgs = sawAnnotation
                            && previousKind == .symbol(.rParen)
                        if let previousKind,
                           !Self.isAnonymousFunctionTypeConnector(previousKind),
                           !followsAnnotationArgs {
                            break typeScan
                        }
                    case .keyword(.suspend), .keyword(.dynamic):
                        if previousKind != nil {
                            break typeScan
                        }
                    case .keyword:
                        break typeScan
                    default:
                        break
                    }
                }
                if token.kind == .symbol(.at) {
                    sawAnnotation = true
                }
                depth.track(token.kind)
                previousKind = token.kind
                _ = consume()
            }
        }

        let expressionBody: ExprID?
        let headerEndIndex = index
        if matches(.symbol(.assign)) {
            // Context and extension receiver expression bodies still require
            // their existing rejection until their closure lowering is fixed.
            // A lone `<...>` type parameter clause is not a receiver —
            // kotlinc accepts `fun <T>(x: T) = x` (it only prohibits the
            // type parameters themselves, reported above).
            if (functionStartIndex != expressionStartIndex
                || (lParenIndex != functionStartIndex + 1
                    && tokens[functionStartIndex + 1].kind != .symbol(.lessThan))),
               let token = current() {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0001",
                    "Expected '{' for anonymous function body.",
                    range: token.range
                )
            }
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
            // A bodiless `fun(...)` still parses as an anonymous function;
            // parseLocalFunDeclExpr reports 'must have a body' on it, the
            // same diagnostic kotlinc emits ('function 'anonymous' must
            // have a body.').
            expressionBody = nil
        }
        let endIndex = index

        let syntheticName = label ?? interner.intern(
            "__AnonymousFunction_\(funToken.range.start.file.rawValue)_\(funToken.range.start.offset)"
        )
        let nameToken = Token(kind: .identifier(syntheticName), range: funToken.range)
        var synthTokens = Array(tokens[expressionStartIndex..<functionStartIndex])
        synthTokens.append(contentsOf: tokens[functionStartIndex..<lParenIndex])
        synthTokens.append(nameToken)
        synthTokens.append(contentsOf: tokens[lParenIndex..<(expressionBody == nil ? endIndex : headerEndIndex)])

        let phase = BuildASTPhase(diagnostics: diagnostics)
        guard let localFunExprID = phase.parseLocalFunDeclExpr(
            from: synthTokens, interner: interner, astArena: astArena,
            bodyOverride: expressionBody.flatMap { body in
                astArena.exprRange(body).map { .expr(body, $0) }
            },
            isAnonymousFunction: true
        ) else {
            index = expressionStartIndex
            return nil
        }
        astArena.markAnonymousFunction(localFunExprID)

        let range = SourceRange(start: tokens[expressionStartIndex].range.start, end: tokens[endIndex - 1].range.end)
        let callableRefID = astArena.appendExpr(.callableRef(receiver: nil, member: syntheticName, range: range))
        let function = astArena.appendExpr(.blockExpr(statements: [localFunExprID], trailingExpr: callableRefID, range: range))
        astArena.markAnonymousFunction(localFunExprID)
        astArena.markAnonymousFunction(function)
        return function
    }

    /// Tokens after which an identifier can still continue a return-type
    /// spelling (qualified names, function types, generic arguments,
    /// `suspend`). Everything else means the type is complete.
    private static func isAnonymousFunctionTypeConnector(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.dot), .symbol(.questionDot), .symbol(.arrow),
             .symbol(.lessThan), .symbol(.at), .keyword(.suspend),
             .softKeyword(.context):
            return true
        default:
            return false
        }
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
