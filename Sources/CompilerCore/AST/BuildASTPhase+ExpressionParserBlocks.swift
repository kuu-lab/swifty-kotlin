
extension BuildASTPhase.ExpressionParser {
    func parseBlockExpression() -> ExprID? {
        guard let openBrace = consume() else {
            return nil
        }
        var depth = 1
        var blockTokens: [Token] = []
        var end = openBrace.range.end

        while let token = current() {
            _ = consume()
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
                blockTokens.append(token)
            case .symbol(.rBrace):
                depth -= 1
                if depth == 0 {
                    end = token.range.end
                    break
                }
                blockTokens.append(token)
            default:
                blockTokens.append(token)
            }
            if depth == 0 {
                break
            }
        }

        let ranges = splitBlockTokensIntoStatementRanges(blockTokens)
        if ranges.isEmpty {
            let range = SourceRange(start: openBrace.range.start, end: end)
            return astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: range))
        }

        var statements: [ExprID] = []
        let allTokens = blockTokens[...]
        let localFunctionParser = BuildASTPhase(diagnostics: diagnostics)
        for (rangeIndex, (start, rangeEnd)) in ranges.enumerated() {
            let group = allTokens[start ..< rangeEnd]
            guard !group.isEmpty else { continue }
            // A statement-initial annotation now reaches the group merged with
            // its operand (`@Suppress("X")\nfun f()`); the fun/decl parsers
            // need it stripped like parseStatementGroup does. Assignment and
            // expression paths keep the raw group so annotations still attach
            // to the parsed expression.
            let strippedGroup = BuildASTPhase.skipLeadingLocalAnnotations(
                Array(group), interner: interner
            )
            if let localFun = localFunctionParser.parseLocalFunDeclExpr(
                from: strippedGroup, interner: interner, astArena: astArena
            ) {
                statements.append(localFun)
            } else if let localDecl = parseLocalDeclFromSlice(group) {
                statements.append(localDecl)
            } else if rangeIndex == ranges.count - 1,
                      let postfixExpr = parseTrailingScalarPostfixMutation(strippedGroup[...])
            {
                statements.append(postfixExpr)
            } else if let localAssign = parseLocalAssignFromSlice(group) {
                statements.append(localAssign)
            } else if let nominalDecl = BuildASTPhase.parseLocalNominalDeclExpr(
                from: Array(group), interner: interner, astArena: astArena, diagnostics: diagnostics
            ) {
                statements.append(nominalDecl)
            } else if let expr = BuildASTPhase.ExpressionParser(
                tokens: group, interner: interner, astArena: astArena, diagnostics: diagnostics
            ).parse() {
                statements.append(expr)
            }
        }

        var trailingExpr: ExprID?
        if let lastID = statements.last, let lastExpr = astArena.expr(lastID) {
            switch lastExpr {
            case .localDecl, .localAssign, .memberAssign, .safeMemberAssign, .indexedAssign, .compoundAssign, .indexedCompoundAssign, .memberCompoundAssign, .localFunDecl, .localNominalDecl:
                break
            default:
                trailingExpr = statements.removeLast()
            }
        }

        let range = SourceRange(start: openBrace.range.start, end: end)
        return astArena.appendExpr(.blockExpr(statements: statements, trailingExpr: trailingExpr, range: range))
    }

    private func parseTrailingScalarPostfixMutation(_ tokens: ArraySlice<Token>) -> ExprID? {
        var expressionTokens = Array(tokens)
        while expressionTokens.last?.kind == .symbol(.semicolon) {
            expressionTokens.removeLast()
        }
        guard let lastToken = expressionTokens.last else { return nil }
        switch lastToken.kind {
        case .symbol(.plusPlus), .symbol(.minusMinus):
            break
        default:
            return nil
        }

        let parser = BuildASTPhase.ExpressionParser(
            tokens: expressionTokens,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
        guard let expression = parser.parse(),
              parser.index == parser.tokens.endIndex,
              !parser.hasIncompleteExpression,
              let expressionNode = astArena.expr(expression),
              case let .blockExpr(statements, trailingExpr, _) = expressionNode,
              trailingExpr != nil,
              let mutation = statements.last,
              astArena.isIncrementDecrement(mutation)
        else {
            return nil
        }

        // Keep indexed increments on the indexed-assignment path; this expression-value fix is
        // limited to scalar name/member mutations and their old-value result.
        switch astArena.expr(mutation) {
        case .compoundAssign, .memberCompoundAssign:
            return expression
        default:
            return nil
        }
    }

    func splitBlockTokensIntoStatementRanges(_ tokens: [Token]) -> [(Int, Int)] {
        var ranges: [(Int, Int)] = []
        var groupStart = 0
        var lastTokenIndex = -1
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var unpairedTopLevelIfCount = 0
        for (idx, token) in tokens.enumerated() {
            let isTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if isTopLevel {
                if token.kind == .symbol(.semicolon) {
                    // Kotlin permits a statement separator between an unbraced
                    // if branch and its else branch, including across a newline.
                    if unpairedTopLevelIfCount > 0,
                       tokens.indices.contains(idx + 1),
                       tokens[idx + 1].kind == .keyword(.else)
                    {
                        lastTokenIndex = idx
                        continue
                    }
                    if lastTokenIndex >= groupStart {
                        ranges.append((groupStart, lastTokenIndex + 1))
                    }
                    groupStart = idx + 1
                    unpairedTopLevelIfCount = 0
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline, lastTokenIndex >= groupStart,
                   !(token.kind == .keyword(.else) && unpairedTopLevelIfCount > 0),
                   !BuildASTPhase.isContinuationBoundary(
                       previousTail: tokens[groupStart ... lastTokenIndex],
                       nextHead: tokens[idx...]
                   )
                {
                    ranges.append((groupStart, lastTokenIndex + 1))
                    groupStart = idx
                    unpairedTopLevelIfCount = 0
                }
                if token.kind == .keyword(.if) {
                    unpairedTopLevelIfCount += 1
                } else if token.kind == .keyword(.else) {
                    unpairedTopLevelIfCount = max(0, unpairedTopLevelIfCount - 1)
                }
            }
            switch token.kind {
            case .symbol(.lParen): parenDepth += 1
            case .symbol(.rParen): parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket): bracketDepth += 1
            case .symbol(.rBracket): bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
            lastTokenIndex = idx
        }
        if lastTokenIndex >= groupStart {
            ranges.append((groupStart, lastTokenIndex + 1))
        }
        return ranges
    }

    func parseLocalDeclFromSlice(
        _ tokens: ArraySlice<Token>,
        suppressesLocalModifierDiagnostics: Bool = false,
        requiresCompleteInitializer: Bool = false
    ) -> ExprID? {
        let interner = interner
        let astArena = astArena
        // A statement-initial annotation merged with the declaration by the
        // newline splitter (`@Suppress("X")\nval x = ...`) cannot reach the
        // val/var head; strip it like parseStatementGroup does — the
        // annotation itself is still dropped.
        let labeledTokens = BuildASTPhase.skipLeadingLocalDeclarationLabels(Array(tokens))
        let tokens = BuildASTPhase.skipLeadingLocalAnnotations(
            labeledTokens, interner: interner
        )[...]
        // Nested blocks (if/while/lambda bodies) reach declarations through this
        // slice-based path, so destructuring has to be recognised here too;
        // otherwise `val (a, b) = expr` degrades into `val a = expr`.
        if let destructuring = BuildASTPhase.parseDestructuringDeclarationStatement(
            from: Array(tokens),
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics,
            suppressesLocalModifierDiagnostics: suppressesLocalModifierDiagnostics
        ) {
            return destructuring
        }
        let context = BuildASTPhase.LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { slice in
                let parser = BuildASTPhase.ExpressionParser(
                    tokens: slice, interner: interner, astArena: astArena, diagnostics: self.diagnostics
                )
                guard let expression = parser.parse() else { return nil }
                if requiresCompleteInitializer,
                   parser.index != slice.endIndex || parser.hasIncompleteExpression {
                    return nil
                }
                return expression
            },
            parseTypeReference: { typeTokens in
                guard let first = typeTokens.first else {
                    return nil
                }
                let parser = BuildASTPhase.ExpressionParser(
                    tokens: typeTokens,
                    interner: interner,
                    astArena: astArena,
                    diagnostics: self.diagnostics
                )
                // A local `val`/`var` type annotation is a declaration type:
                // the tokens are already bounded by `=`/newline, so function
                // types (`(T) -> U`, `R.() -> U`, `suspend R.() -> U`) parse
                // unambiguously — unlike is/as operands, which share the
                // arrow token with `when` branches and stay non-functional.
                return parser.parseTypeReference(first.range, allowFunctionType: true)
            },
            resolveDeclarationName: { token, interner in
                guard TypeRefParserCore.isDeclarationNameToken(token.kind) else {
                    return nil
                }
                switch token.kind {
                case let .identifier(name), let .backtickedIdentifier(name):
                    return name
                case let .keyword(keyword):
                    return interner.intern(keyword.rawValue)
                case let .softKeyword(keyword):
                    return interner.intern(keyword.rawValue)
                default:
                    return nil
                }
            }
        )
        return BuildASTPhase.LocalStatementCore.parseLocalDeclaration(
            from: tokens,
            context: context,
            options: requiresCompleteInitializer ? .declaration : .blockExpression
        )
    }

    func parseLocalAssignFromSlice(_ tokens: ArraySlice<Token>) -> ExprID? {
        let interner = interner
        let astArena = astArena
        let context = BuildASTPhase.LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { slice in
                BuildASTPhase.ExpressionParser(
                    tokens: slice, interner: interner, astArena: astArena, diagnostics: self.diagnostics
                ).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil }
        )
        return BuildASTPhase.LocalStatementCore.parseLocalAssignment(
            from: tokens,
            context: context,
            options: .blockExpression
        )
    }

    func skipBalancedParenthesisIfNeeded() {
        guard matches(.symbol(.lParen)) else {
            return
        }
        _ = consume()
        var depth = 1
        while let token = current(), depth > 0 {
            _ = consume()
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
            default:
                continue
            }
        }
    }

}
