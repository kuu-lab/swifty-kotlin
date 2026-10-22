
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

        var statements = parseLambdaBodyStatements(ranges: ranges, tokens: bodyTokens)
        guard !statements.isEmpty else {
            return nil
        }

        let hasStatementOnlyBody = statements.contains { statementID in
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
            // Keep a final postfix mutation as an expression so the lambda returns its old value.
            if rangeIndex == ranges.count - 1,
               let postfixExpr = parseTrailingScalarPostfixMutation(group)
            {
                statements.append(postfixExpr)
            } else if let statementExpr = parseLambdaBodyStatement(from: group) {
                statements.append(statementExpr)
            }
        }
        return statements
    }

    private func parseLambdaBodyStatement(from group: ArraySlice<Token>) -> ExprID? {
        let phase = BuildASTPhase(diagnostics: diagnostics)
        if let localFun = phase.parseLocalFunDeclExpr(
            from: Array(group), interner: interner, astArena: astArena
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
