
extension BuildASTPhase.ExpressionParser {
    func parseLambdaBody(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> ExprID {
        if let blockExpr = parseLambdaBodyAsBlockExpression(
            bodySlice: bodySlice,
            fallbackStart: fallbackStart
        ) {
            return blockExpr
        }

        if let parsedExpr = BuildASTPhase.ExpressionParser(
            tokens: bodySlice,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        ).parse() {
            return parsedExpr
        }

        return astArena.appendExpr(.blockExpr(
            statements: [],
            trailingExpr: nil,
            range: lambdaBodyRange(bodySlice: bodySlice, fallbackStart: fallbackStart)
        ))
    }

    private func parseLambdaBodyAsBlockExpression(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> ExprID? {
        let bodyTokens = Array(bodySlice)
        let ranges = splitBlockTokensIntoStatementRanges(bodyTokens)
        guard !ranges.isEmpty else {
            return nil
        }

        // The caller reparses the tokens as an expression when this probe
        // cannot form a block, so discarded diagnostics must not leak.
        let diagnosticsCheckpoint = diagnostics?.checkpoint()
        func rollbackSpeculativeDiagnostics() {
            if let diagnosticsCheckpoint {
                diagnostics?.rollback(to: diagnosticsCheckpoint)
            }
        }
        var statements = parseLambdaBodyStatements(ranges: ranges, tokens: bodyTokens)
        guard !statements.isEmpty else {
            rollbackSpeculativeDiagnostics()
            return nil
        }

        let hasStatementOnlyBody = statements.contains { statementID in
            // Compound assignments on non-assignable targets (`this += x`,
            // `a?.b += x`, call results) desugar to a marked blockExpr — still
            // a statement, never a value-producing tail.
            if astArena.isCallResultCompoundAssignmentBlock(statementID) {
                return true
            }
            guard let statement = astArena.expr(statementID) else { return false }
            switch statement {
            case .localDecl, .localAssign, .memberAssign, .safeMemberAssign, .indexedAssign,
                 .compoundAssign, .indexedCompoundAssign, .memberCompoundAssign,
                 .localFunDecl, .localNominalDecl:
                return true
            default:
                return false
            }
        }
        // A leading empty statement is omitted from `ranges`, so a single
        // expression after it must stay a block body with a trailing value.
        if ranges.count == 1, !hasStatementOnlyBody, ranges[0].0 == 0 {
            rollbackSpeculativeDiagnostics()
            return nil
        }

        let trailingExpr = lambdaTrailingExpression(from: &statements)
        return astArena.appendExpr(.blockExpr(
            statements: statements,
            trailingExpr: trailingExpr,
            range: lambdaBodyRange(bodySlice: bodySlice, fallbackStart: fallbackStart)
        ))
    }

    private func parseLambdaBodyStatements(
        ranges: [(Int, Int)],
        tokens: [Token]
    ) -> [ExprID] {
        var statements: [ExprID] = []
        for (rangeIndex, (start, end)) in ranges.enumerated() {
            let group = ArraySlice(tokens[start ..< end])
            guard !group.isEmpty else {
                continue
            }
            // Keep a final indexed mutation as an expression so the lambda returns
            // the old value for postfix or the updated value for prefix.
            if rangeIndex == ranges.count - 1,
               let prefixExpr = parseTrailingPrefixMutation(group)
            {
                statements.append(prefixExpr)
            } else if rangeIndex == ranges.count - 1,
               let postfixExpr = parseTrailingPostfixMutation(group)
            {
                statements.append(postfixExpr)
            } else if let statementExpr = parseLambdaBodyStatement(from: group) {
                BuildASTPhase(diagnostics: diagnostics).validateLocalFunctionSeparator(
                    after: statementExpr, in: tokens, astArena: astArena
                )
                statements.append(statementExpr)
            }
        }
        return statements
    }

    private func parseLambdaBodyStatement(from group: ArraySlice<Token>) -> ExprID? {
        let phase = BuildASTPhase(diagnostics: diagnostics)
        if let localFun = phase.parseLocalFunDeclExpr(
            from: Array(group),
            interner: interner, astArena: astArena
        ) {
            return localFun
        }
        if let localDecl = parseLocalDeclFromSlice(group) {
            return localDecl
        }
        if let localAssign = parseLocalAssignFromSlice(group) {
            return localAssign
        }
        if let nominalDecl = BuildASTPhase.parseLocalNominalDeclExpr(
            from: Array(group), interner: interner, astArena: astArena, diagnostics: diagnostics
        ) {
            return nominalDecl
        }
        return BuildASTPhase.ExpressionParser(
            tokens: group,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        ).parse()
    }

    private func parseTrailingPrefixMutation(_ tokens: ArraySlice<Token>) -> ExprID? {
        var expressionTokens = Array(tokens)
        while expressionTokens.last?.kind == .symbol(.semicolon) {
            expressionTokens.removeLast()
        }
        guard let firstToken = expressionTokens.first,
              firstToken.kind == .symbol(.plusPlus) || firstToken.kind == .symbol(.minusMinus)
        else {
            return nil
        }

        // This whole parse is speculative: on bail the token group is reparsed
        // as a statement or a plain expression, so its diagnostics must not leak.
        let diagnosticsCheckpoint = diagnostics?.checkpoint()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: expressionTokens,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
        guard let expression = parser.parse(),
              parser.index == parser.tokens.endIndex,
              !parser.hasIncompleteExpression,
              case let .blockExpr(statements, trailingExpr, _) = astArena.expr(expression),
              let trailingExpr,
              case .indexedAccess = astArena.expr(trailingExpr),
              let mutation = statements.last,
              case let .indexedAssign(_, _, valueExpr, _) = astArena.expr(mutation),
              case let .memberCall(_, callee, typeArgs, args, _) = astArena.expr(valueExpr),
              typeArgs.isEmpty,
              args.isEmpty,
              astArena.isExplicitCall(valueExpr)
        else {
            if let diagnosticsCheckpoint {
                diagnostics?.rollback(to: diagnosticsCheckpoint)
            }
            return nil
        }

        let name = interner.resolve(callee)
        guard name == "inc" || name == "dec" else {
            if let diagnosticsCheckpoint {
                diagnostics?.rollback(to: diagnosticsCheckpoint)
            }
            return nil
        }
        return expression
    }

    private func lambdaTrailingExpression(from statements: inout [ExprID]) -> ExprID? {
        guard let lastID = statements.last, let lastExpr = astArena.expr(lastID) else {
            return nil
        }

        switch lastExpr {
        case .localDecl, .localAssign, .memberAssign, .safeMemberAssign, .indexedAssign,
             .compoundAssign, .indexedCompoundAssign, .memberCompoundAssign,
             .localFunDecl, .localNominalDecl:
            return nil
        default:
            if astArena.isCallResultCompoundAssignmentBlock(lastID) {
                return nil
            }
            _ = statements.popLast()
            return lastID
        }
    }

    private func lambdaBodyRange(
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation
    ) -> SourceRange {
        if let firstToken = bodySlice.first, let lastToken = bodySlice.last {
            return SourceRange(start: firstToken.range.start, end: lastToken.range.end)
        }
        return SourceRange(start: fallbackStart, end: fallbackStart)
    }
}
