
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
        let parsedStatements = parseLambdaBodyStatements(ranges: ranges, tokens: bodyTokens)
        var statements = parsedStatements.statements
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
            // The statement probe already ran the same ExpressionParser the
            // expression fallback in `parseLambdaBody` would run on these
            // tokens. Reuse that parse: reparsing the body doubled the work
            // at every lambda nesting level, so deeply nested lambda bodies
            // (e.g. arity-N `curried()` chains) compiled in exponential time.
            if let statement = statements.first,
               parsedStatements.plainExpressionParses.contains(statement)
            {
                return statement
            }
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

    /// Parses each statement range. `plainExpressionParses` collects the
    /// statements that came from the plain `ExpressionParser.parse()`
    /// fallback inside `parseLambdaBodyStatement` — the same parse
    /// `parseLambdaBody` would run on the whole body when it is a single
    /// expression — so the caller can reuse them instead of reparsing.
    private func parseLambdaBodyStatements(
        ranges: [(Int, Int)],
        tokens: [Token]
    ) -> (statements: [ExprID], plainExpressionParses: Set<ExprID>) {
        var statements: [ExprID] = []
        var plainExpressionParses: Set<ExprID> = []
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
            } else if let statement = parseLambdaBodyStatement(from: group) {
                BuildASTPhase(diagnostics: diagnostics).validateLocalFunctionSeparator(
                    after: statement.expr, in: tokens, astArena: astArena
                )
                statements.append(statement.expr)
                if statement.isPlainExpressionParse {
                    plainExpressionParses.insert(statement.expr)
                }
            }
        }
        return (statements, plainExpressionParses)
    }

    /// `isPlainExpressionParse` is true only when the statement came from the
    /// trailing `ExpressionParser.parse()` fallback — declaration and
    /// mutation probes return shaped results the expression fallback would
    /// not reproduce, so they must keep the reparse path.
    private func parseLambdaBodyStatement(
        from group: ArraySlice<Token>
    ) -> (expr: ExprID, isPlainExpressionParse: Bool)? {
        let phase = BuildASTPhase(diagnostics: diagnostics)
        // Every probe is speculative, matching parseStatementGroup and
        // parseBlockExpression: a failing attempt can emit diagnostics for a
        // parse the group is then reparsed without — e.g. the assignment
        // probe splits `fun(): Int = it * it` at `=` and parses the LHS as a
        // bodiless anonymous function, leaking 'must have a body'. Roll those
        // back; only the winning parse keeps its diagnostics.
        let speculationCheckpoint = diagnostics?.checkpoint()
        func undoFailedSpeculation() {
            if let speculationCheckpoint {
                diagnostics?.rollback(to: speculationCheckpoint)
            }
        }
        if let localFun = phase.parseLocalFunDeclExpr(
            from: Array(group),
            interner: interner, astArena: astArena
        ) {
            return (localFun, false)
        }
        undoFailedSpeculation()
        if let localDecl = parseLocalDeclFromSlice(group) {
            return (localDecl, false)
        }
        if let first = group.first,
           first.kind == .keyword(.val) || first.kind == .keyword(.var),
           diagnostics?.checkpoint() != speculationCheckpoint
        {
            // Keep diagnostics from a malformed initializer in a declaration
            // inside a lambda body. A declaration-shaped placeholder prevents
            // the enclosing lambda probe from rolling the diagnostic back.
            guard let nameToken = group.dropFirst().first(where: {
                TypeRefParserCore.isDeclarationNameToken($0.kind)
            }),
               let name = tokenText(nameToken)
            else {
                undoFailedSpeculation()
                return nil
            }
            return (astArena.appendExpr(.localDecl(
                name: name,
                isMutable: first.kind == .keyword(.var),
                typeAnnotation: nil,
                initializer: nil,
                isDelegated: false,
                isLateinit: false,
                range: SourceRange(start: first.range.start, end: group.last?.range.end ?? first.range.end)
            )), false)
        }
        undoFailedSpeculation()
        if let localAssign = parseLocalAssignFromSlice(group) {
            return (localAssign, false)
        }
        undoFailedSpeculation()
        if let nominalDecl = BuildASTPhase.parseLocalNominalDeclExpr(
            from: Array(group), interner: interner, astArena: astArena, diagnostics: diagnostics
        ) {
            return (nominalDecl, false)
        }
        undoFailedSpeculation()
        guard let expression = BuildASTPhase.ExpressionParser(
            tokens: group,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        ).parse() else {
            return nil
        }
        return (expression, true)
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
