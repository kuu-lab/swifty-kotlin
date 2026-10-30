
extension BuildASTPhase.ExpressionParser {
    /// Returns whether an assignment operator was diagnosed.
    @discardableResult
    private func diagnoseAssignmentOperatorAfterExpression() -> Bool {
        guard let token = current() else { return false }
        switch token.kind {
        case .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
             .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign):
            diagnostics?.error(
                "KSWIFTK-PARSE-0018",
                "Unexpected token after expression.",
                range: token.range
            )
            return true
        default:
            return false
        }
    }

    private func parseRequiredControlFlowCondition() -> ExprID? {
        if let token = current(), token.kind == .symbol(.rParen) {
            diagnostics?.error("KSWIFTK-PARSE-0001", "Expected expression.", range: token.range)
            // Preserve the control-flow node so surrounding declarations don't cascade into name errors.
            return astArena.appendExpr(.boolLiteral(false, token.range))
        }
        return parseExpression(minPrecedence: 0)
    }

    /// Records a trailing `else` (optionally preceded by `;`) that follows a
    /// completed control-flow expression. An enclosing if may still claim it
    /// as its dangling else; `parse()` diagnoses it if no if does.
    private func recordStrayElseIfPresent() {
        if matches(.keyword(.else)) {
            strayElseToken = current()
        } else if matches(.symbol(.semicolon)), peek(1)?.kind == .keyword(.else) {
            strayElseToken = peek(1)
        }
    }

    private func parseControlFlowBodyExpression() -> ExprID? {
        if let token = current(), token.kind == .symbol(.semicolon) {
            _ = consume()
            return astArena.appendExpr(
                .blockExpr(statements: [], trailingExpr: nil, range: token.range)
            )
        }
        if matches(.symbol(.lBrace)) {
            if braceGroupStartsLambdaLiteral(), let lambda = parseLambdaLiteral() {
                return lambda
            }
            return parseBlockExpression()
        }
        let startIndex = index
        if startIndex < tokens.endIndex {
            let remaining = Array(tokens[startIndex ..< tokens.endIndex])
            let statementRanges = splitBlockTokensIntoStatementRanges(remaining)
            if let (statementStart, statementEnd) = statementRanges.first,
               statementStart == 0,
               statementEnd > statementStart
            {
                let bodyEnd = controlFlowStatementEnd(in: remaining, before: statementEnd)
                let bodySlice = remaining[statementStart ..< bodyEnd]
                if let localDecl = parseLocalDeclFromSlice(bodySlice[...]) {
                    index = startIndex + bodyEnd
                    return localDecl
                }
                if let localAssign = parseLocalAssignFromSlice(bodySlice[...]) {
                    index = startIndex + bodyEnd
                    return localAssign
                }
            }
        }
        if matches(.symbol(.at)) {
            guard let operand = parseAnnotatedExpression({
                if self.matches(.symbol(.lBrace)) {
                    return self.parseControlFlowBodyExpression()
                }
                return self.parsePrefixUnary()
            }) else { return nil }
            return parseInfixOperators(lhs: operand, minPrecedence: 0)
        }
        return parseExpression(minPrecedence: 0)
    }

    /// A single assignment body must leave its enclosing `else` for the if
    /// parser. Statement splitting deliberately keeps if/else on one line;
    /// consuming that whole slice here would silently discard the else body.
    private func controlFlowStatementEnd(in tokens: [Token], before end: Int) -> Int {
        var depth = BuildASTPhase.BracketDepth()
        var nestedIfs = 0
        for offset in 0 ..< end {
            let token = tokens[offset]
            if depth.isAtTopLevel {
                if token.kind == .keyword(.if) {
                    nestedIfs += 1
                } else if token.kind == .keyword(.else) {
                    if nestedIfs == 0 { return offset }
                    nestedIfs -= 1
                }
            }
            // Angle tokens can be comparison operators. Type arguments cannot
            // contain an if/else branch, so only expression delimiters matter.
            if token.kind != .symbol(.lessThan), token.kind != .symbol(.greaterThan) {
                depth.track(token.kind)
            }
        }
        return end
    }

    func parseWhenExpression() -> ExprID? {
        guard let whenToken = consume() else {
            return nil
        }
        var subject: ExprID?
        var subjectVarName: InternedString?
        var subjectTypeRef: TypeRefID?
        var headerMalformed = false
        if matches(.symbol(.lParen)) {
            _ = consume()
            if matches(.keyword(.val)),
               let identToken = peek(1),
               let varName = whenSubjectVariableName(from: identToken)
            {
                subjectVarName = varName
                _ = consume()
                _ = consume()
                if let colon = consumeIf(.symbol(.colon)) {
                    guard let typeRef = parseTypeReference(colon.range, allowFunctionType: true) else {
                        return nil
                    }
                    subjectTypeRef = typeRef
                }
                guard consumeIf(.symbol(.assign)) != nil else {
                    if let token = current() {
                        diagnostics?.error(
                            "KSWIFTK-PARSE-0010",
                            "Expected '=' after 'when' subject variable.",
                            range: token.range
                        )
                    }
                    return nil
                }
            }
            if matches(.symbol(.rParen)) {
                if let token = current() {
                    diagnostics?.error("KSWIFTK-PARSE-0001", "Expected expression.", range: token.range)
                    headerMalformed = true
                }
            } else {
                subject = parseExpression(minPrecedence: 0)
                if subject != nil {
                    headerMalformed = diagnoseAssignmentOperatorAfterExpression()
                } else if let token = current() {
                    diagnostics?.error("KSWIFTK-PARSE-0001", "Expected expression.", range: token.range)
                    headerMalformed = true
                }
            }
            _ = consumeIf(.symbol(.rParen))
        }
        guard consumeIf(.symbol(.lBrace)) != nil else {
            if !headerMalformed {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0010",
                    "Expected '{' after 'when'.",
                    range: current()?.range ?? whenToken.range
                )
            }
            return nil
        }

        var branches: [WhenBranch] = []
        var elseExpr: ExprID?
        var hasSeenElseBranch = false
        var hasReportedElseBranchPosition = false
        var end = whenToken.range.end

        while let token = current() {
            let loopStart = index
            if token.kind == .symbol(.rBrace) {
                end = token.range.end
                _ = consume()
                break
            }

            if hasSeenElseBranch, !hasReportedElseBranchPosition {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0027",
                    "The 'else' branch must be the last branch in a 'when' expression.",
                    range: token.range
                )
                hasReportedElseBranchPosition = true
            }

            let branchStart = token.range.start
            var conditions: [ExprID] = []
            var isElseBranch = false
            if token.kind == .keyword(.else) {
                _ = consume()
                isElseBranch = true
            } else {
                if matches(.symbol(.arrow)) {
                    diagnostics?.error("KSWIFTK-PARSE-0011", "Expected when branch condition.", range: token.range)
                }
                let firstCond = parseWhenBranchCondition(subject: subject)
                diagnoseAssignmentOperatorAfterExpression()
                if let firstCond {
                    conditions.append(firstCond)
                }
                while matches(.symbol(.comma)) {
                    _ = consume()
                    // If we see '->' after comma, it was a trailing comma; stop
                    if matches(.symbol(.arrow)) {
                        break
                    }
                    let nextCond = parseWhenBranchCondition(subject: subject)
                    diagnoseAssignmentOperatorAfterExpression()
                    guard let nextCond else {
                        break
                    }
                    conditions.append(nextCond)
                }
            }

            var guardExpr: ExprID?
            if isElseBranch {
                // Kotlin 2.1 when guards: `else if <expr> ->` is a fallible
                // catch-all branch — not the final `else` — so further
                // branches (including a plain `else`) may still follow.
                if matches(.keyword(.if)) {
                    _ = consume()
                    guardExpr = parseExpression(minPrecedence: 0)
                    diagnoseAssignmentOperatorAfterExpression()
                    isElseBranch = false
                } else {
                    hasSeenElseBranch = true
                }
            } else if !conditions.isEmpty, matches(.keyword(.if)) {
                _ = consume()
                guardExpr = parseExpression(minPrecedence: 0)
                diagnoseAssignmentOperatorAfterExpression()
            }

            _ = consumeIf(.symbol(.arrow))
            let body = parseWhenBranchBodyExpression()
            while matches(.symbol(.semicolon)) || matches(.symbol(.comma)) {
                _ = consume()
            }

            if let body {
                let branchRange = SourceRange(start: branchStart, end: astArena.exprRange(body)?.end ?? branchStart)
                let branch = WhenBranch(conditions: conditions, guard: guardExpr, body: body, range: branchRange)
                if isElseBranch {
                    elseExpr = body
                } else if !conditions.isEmpty || guardExpr != nil {
                    branches.append(branch)
                }
                end = branchRange.end
            }

            // Progress guard: force token consumption to avoid infinite loops.
            if index == loopStart {
                _ = consume()
            }
        }

        let range = SourceRange(start: whenToken.range.start, end: end)
        let whenExprID = astArena.appendExpr(.whenExpr(subject: subject, branches: branches, elseExpr: elseExpr, range: range))
        if let subjectVarName {
            astArena.setWhenSubjectVarName(subjectVarName, for: whenExprID)
        }
        if let subjectTypeRef {
            astArena.setWhenSubjectTypeRef(subjectTypeRef, for: whenExprID)
        }
        return whenExprID
    }

    private func whenSubjectVariableName(from token: Token) -> InternedString? {
        switch token.kind {
        case .identifier, .backtickedIdentifier, .softKeyword:
            return tokenText(token)
        case let .keyword(keyword) where KotlinParser.isDeclarationModifierKeyword(keyword):
            return tokenText(token)
        default:
            return nil
        }
    }

    private func parseWhenBranchCondition(subject: ExprID?) -> ExprID? {
        if let subject,
           let token = current()
        {
            if token.kind == .keyword(.is) {
                _ = consume()
                guard let typeRef = parseTypeReference(token.range, allowFunctionType: true) else {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0005",
                        "Expected type after 'is'.",
                        range: current()?.range ?? token.range
                    )
                    return nil
                }
                let conditionRange = mergeRanges(astArena.exprRange(subject), nil, fallback: token.range)
                return astArena.appendExpr(.isCheck(expr: subject, type: typeRef, negated: false, range: conditionRange))
            }
            if token.kind == .symbol(.bang),
               let isToken = peek(1),
               isToken.kind == .keyword(.is)
            {
                _ = consume()
                _ = consume()
                guard let typeRef = parseTypeReference(token.range, allowFunctionType: true) else {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0005",
                        "Expected type after 'is'.",
                        range: current()?.range ?? token.range
                    )
                    return nil
                }
                let conditionRange = mergeRanges(astArena.exprRange(subject), nil, fallback: token.range)
                return astArena.appendExpr(.isCheck(expr: subject, type: typeRef, negated: true, range: conditionRange))
            }
            let negatedIn: Bool? = if token.kind == .keyword(.in) {
                false
            } else if token.kind == .symbol(.bang), let inToken = peek(1), inToken.kind == .keyword(.in) {
                true
            } else {
                nil
            }
            if let negatedIn {
                _ = consume()
                if negatedIn { _ = consume() }
                guard let rangeExpr = parseExpression(minPrecedence: 0) else {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0001",
                        "Expected expression after 'in'.",
                        range: current()?.range ?? token.range
                    )
                    return nil
                }
                let conditionRange = mergeRanges(
                    astArena.exprRange(subject), astArena.exprRange(rangeExpr), fallback: token.range
                )
                return astArena.appendExpr(
                    negatedIn
                        ? .notInExpr(lhs: subject, rhs: rangeExpr, range: conditionRange)
                        : .inExpr(lhs: subject, rhs: rangeExpr, range: conditionRange)
                )
            }
        }
        return parseExpression(minPrecedence: 0)
    }

    private func parseWhenBranchBodyExpression() -> ExprID? {
        let startIndex = index
        guard startIndex < tokens.endIndex else {
            return nil
        }

        let endIndex = findWhenBranchBodyEnd(startIndex: startIndex)
        guard endIndex > startIndex else {
            return nil
        }

        let branchTokens = tokens[startIndex ..< endIndex]
        let parser = BuildASTPhase.ExpressionParser(
            tokens: branchTokens,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
        // A bare (non-block) branch body may be an assignment
        // (`1 -> x = 10`, `1 -> counter += 1`, `1 -> arr[i] = v`), which is a
        // statement form the generic expression parser below doesn't know —
        // it only consumes the assignment's target and stops at `=`. The
        // leftover `=` is therefore expected here, not a stray token.
        parser.reportsTrailingAssignmentOperator = false
        var body: ExprID?
        if branchTokens.first?.kind == .symbol(.at) || branchTokens.first?.kind == .symbol(.lBrace) {
            body = parser.parseControlFlowBodyExpression()
        } else {
            body = parser.parse()
        }
        var consumedCount = parser.index - parser.tokens.startIndex
        if body == nil || consumedCount < branchTokens.count {
            if let assignBody = parseWhenBranchAssignmentBody(branchTokens) {
                body = assignBody
                consumedCount = branchTokens.count
            }
        }
        guard let body else {
            return nil
        }

        if consumedCount > 0 {
            index = startIndex + consumedCount
        }
        return body
    }

    private func parseWhenBranchAssignmentBody(_ branchTokens: ArraySlice<Token>) -> ExprID? {
        let context = BuildASTPhase.LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { subTokens in
                BuildASTPhase.ExpressionParser(
                    tokens: subTokens,
                    interner: self.interner,
                    astArena: self.astArena,
                    diagnostics: self.diagnostics
                ).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil },
            diagnostics: self.diagnostics
        )
        return BuildASTPhase.LocalStatementCore.parseLocalAssignment(
            from: branchTokens,
            context: context,
            options: .blockExpression
        )
    }

    private func findWhenBranchBodyEnd(startIndex: Int) -> Int {
        var scan = startIndex
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while scan < tokens.endIndex {
            let token = tokens[scan]
            if parenDepth == 0, bracketDepth == 0, braceDepth == 0 {
                if token.kind == .symbol(.semicolon) || token.kind == .symbol(.rBrace) {
                    return scan
                }
                if scan > startIndex,
                   hasLeadingNewline(token),
                   startsWhenBranchHeader(at: scan)
                {
                    return scan
                }
            }

            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            scan += 1
        }

        return scan
    }

    private func startsWhenBranchHeader(at startIndex: Int) -> Bool {
        guard startIndex < tokens.endIndex else {
            return false
        }

        if tokens[startIndex].kind == .keyword(.else) {
            guard startIndex + 1 < tokens.endIndex else {
                return false
            }
            switch tokens[startIndex + 1].kind {
            case .symbol(.arrow):
                return true
            case .keyword(.if):
                // Kotlin 2.1: `else if <guard> ->` is a fallible catch-all
                // entry rather than the final else — and `else\nif` splits
                // the same way. It is only a header when a `->` actually
                // terminates the guard; otherwise the `else` may belong to
                // an if expression inside the previous body
                // (`1 -> if (a) b\nelse if (c) d else e`).
                return guardedElseReachesArrow(from: startIndex + 2)
            default:
                return false
            }
        }

        var scan = startIndex
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var sawToken = false
        var sawIfKeyword = false

        while scan < tokens.endIndex {
            let token = tokens[scan]

            if parenDepth == 0, bracketDepth == 0, braceDepth == 0 {
                // A guard `if` — and the expression it introduces — may span
                // newlines (`cond\nif g ->`, `cond if\ng ->`), so only other
                // newline-leading tokens disqualify the candidate header.
                if scan > startIndex,
                   hasLeadingNewline(token),
                   !sawIfKeyword, token.kind != .keyword(.if)
                {
                    return false
                }

                if token.kind == .symbol(.arrow) {
                    return sawToken
                }
                if token.kind == .symbol(.semicolon) || token.kind == .symbol(.rBrace) {
                    return false
                }
                if token.kind == .keyword(.if) {
                    sawIfKeyword = true
                }
            }

            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            sawToken = true
            scan += 1
        }

        return false
    }

    /// Whether the tokens after `else if` reach a `->` that terminates a
    /// Kotlin 2.1 guarded else entry. The guard may span newlines; a depth-0
    /// `else` ends the scan because it belongs to an if expression inside
    /// the previous branch body (or to the enclosing construct entirely).
    private func guardedElseReachesArrow(from startIndex: Int) -> Bool {
        var scan = startIndex
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        while scan < tokens.endIndex {
            let token = tokens[scan]
            if parenDepth == 0, bracketDepth == 0, braceDepth == 0 {
                switch token.kind {
                case .symbol(.arrow):
                    return true
                case .keyword(.else), .symbol(.semicolon), .symbol(.rBrace):
                    return false
                default:
                    break
                }
            }
            switch token.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                if parenDepth == 0 { return false }
                parenDepth -= 1
            case .symbol(.lBracket):
                bracketDepth += 1
            case .symbol(.rBracket):
                if bracketDepth == 0 { return false }
                bracketDepth -= 1
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                if braceDepth == 0 { return false }
                braceDepth -= 1
            default:
                break
            }
            scan += 1
        }
        return false
    }

    private func hasLeadingNewline(_ token: Token) -> Bool {
        token.leadingTrivia.contains { piece in
            if case .newline = piece {
                return true
            }
            return false
        }
    }

    func parseReturnExpression() -> ExprID? {
        guard let returnToken = consume() else {
            return nil
        }

        var label: InternedString?
        var end = returnToken.range.end
        if let atToken = current(), atToken.kind == .symbol(.at),
           let labelToken = peek(1),
           let labelName = labelNameFromToken(labelToken)
        {
            _ = consume()
            _ = consume()
            label = labelName
            end = labelToken.range.end
        }

        // An else clause terminates a bare return in the enclosing if branch.
        let value = matches(.keyword(.else)) ? nil : parseExpression(minPrecedence: 0)
        if let value, let valueEnd = astArena.exprRange(value)?.end {
            end = valueEnd
        }
        let range = SourceRange(start: returnToken.range.start, end: end)
        return astArena.appendExpr(.returnExpr(value: value, label: label, range: range))
    }

    func parseThrowExpression() -> ExprID? {
        guard let throwToken = consume() else {
            return nil
        }
        guard let value = parseExpression(minPrecedence: 0) else {
            diagnostics?.error("KSWIFTK-PARSE-0001", "Expected expression.", range: throwToken.range)
            return nil
        }
        let end = astArena.exprRange(value)?.end ?? throwToken.range.end
        let range = SourceRange(start: throwToken.range.start, end: end)
        return astArena.appendExpr(.throwExpr(value: value, range: range))
    }

    func parseForExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let forToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected parenthesized loop header after 'for'.",
                range: current()?.range ?? forToken.range
            )
            return nil
        }

        if matches(.symbol(.lParen)) || matches(.symbol(.lBracket)) {
            let savedIndex = index
            let syntax: ForDestructuringSyntax = matches(.symbol(.lBracket)) ? .squareBrackets : .parentheses
            let closingKind: TokenKind = syntax == .squareBrackets
                ? .symbol(.rBracket)
                : .symbol(.rParen)
            _ = consume()

            var destructuringNames: [InternedString?] = []
            var destructuringProperties: [InternedString?] = []
            var destructuringMutableFlags: [Bool] = []
            var declaringEntryCount = 0
            var foundClosingDelimiter = false
            while let token = current() {
                if token.kind == closingKind {
                    _ = consume()
                    foundClosingDelimiter = true
                    break
                }
                if token.kind == .symbol(.comma) {
                    _ = consume()
                    continue
                }
                // Kotlin 2.4 full-form name-based destructuring prefixes each
                // entry with `val` (`for ((val value) in it)`). `val` is not a
                // label name, so `tokenText` below would silently skip it and
                // flatten the entry to a bare positional name. Record the
                // marker so Sema can tell the full form (name-based) from the
                // bare short form (positional). `var` stays unmarked: kotlinc
                // rejects it in for-headers outright, and swallowing it keeps
                // the historical positional behavior of `for ((var i, ...)`
                // instead of regressing it into a name-lookup error.
                var entryDeclared = false
                if token.kind == .keyword(.val) {
                    entryDeclared = true
                    _ = consume()
                    guard let head = current(),
                          head.kind != closingKind,
                          head.kind != .symbol(.comma)
                    else {
                        continue
                    }
                }
                if let nameToken = current(), let name = tokenText(nameToken) {
                    // Only a bare `_` skips the entry; a backticked `` `_` `` is
                    // a real variable named `_` that the loop body can use.
                    if case .identifier = nameToken.kind, interner.resolve(name) == "_" {
                        destructuringNames.append(nil)
                    } else {
                        destructuringNames.append(name)
                    }
                    _ = consume()
                    var property: InternedString?
                    if consumeIf(.symbol(.assign)) != nil,
                       let propertyToken = current(),
                       let propertyName = tokenText(propertyToken)
                    {
                        if case .identifier = propertyToken.kind,
                           interner.resolve(propertyName) == "_"
                        {
                            property = nil
                        } else {
                            property = propertyName
                        }
                        _ = consume()
                    }
                    destructuringProperties.append(property)
                    destructuringMutableFlags.append(false)
                    if entryDeclared {
                        declaringEntryCount += 1
                    }
                    if matches(.symbol(.colon)) {
                        _ = consume()
                        while let t = current(),
                              t.kind != .symbol(.comma),
                              t.kind != closingKind
                        {
                            _ = consume()
                        }
                    }
                } else {
                    _ = consume()
                }
            }

            if foundClosingDelimiter, !destructuringNames.isEmpty {
                guard consumeIf(.keyword(.in)) != nil else {
                    index = savedIndex
                    return parseForExpressionFallback(forToken: forToken, label: label, start: start)
                }
                guard let iterable = parseExpression(minPrecedence: 0) else {
                    index = savedIndex
                    return parseForExpressionFallback(forToken: forToken, label: label, start: start)
                }
                diagnoseAssignmentOperatorAfterExpression()
                if consumeIf(.symbol(.rParen)) == nil {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0004",
                        "Expected ')' after 'for' loop header.",
                        range: current()?.range ?? forToken.range
                    )
                }
                guard let body = parseControlFlowBodyExpression() else {
                    index = savedIndex
                    return parseForExpressionFallback(forToken: forToken, label: label, start: start)
                }
                let end = astArena.exprRange(body)?.end ?? forToken.range.end
                let range = SourceRange(start: start ?? forToken.range.start, end: end)
                let exprID = astArena.appendExpr(.forDestructuringExpr(
                    names: destructuringNames,
                    iterable: iterable,
                    body: body,
                    syntax: syntax,
                    range: range
                ))
                if declaringEntryCount > 0, declaringEntryCount != destructuringNames.count {
                    // kotlinc: once one entry declares `val`, every entry must
                    // ("Expecting val keyword").
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0029",
                        "Expecting 'val' keyword in destructuring declaration.",
                        range: forToken.range
                    )
                }
                astArena.setDestructuringDeclLayout(
                    DestructuringDeclLayout(
                        syntax: syntax,
                        properties: destructuringProperties,
                        mutableFlags: declaringEntryCount > 0 ? destructuringMutableFlags : []
                    ),
                    for: exprID
                )
                if let label {
                    astArena.setLoopLabel(label, for: exprID)
                }
                return exprID
            } else {
                index = savedIndex
            }
        }

        return parseForExpressionFallback(forToken: forToken, label: label, start: start)
    }

    private func parseForExpressionFallback(forToken: Token, label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        var loopVariableAnnotations: [AnnotationNode] = []
        while let annotationToken = current(), annotationToken.kind == .symbol(.at) {
            let remaining = Array(tokens[index...])
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: remaining, start: 0, interner: interner, allowUseSiteTarget: false
            ), parsed.nextIndex > 0 else {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0001",
                    "Expected annotation name after '@'.",
                    range: annotationToken.range
                )
                break
            }
            if let range = parsed.invalidUseSiteTargetRange {
                diagnostics?.error(
                    "KSWIFTK-PARSE-ANNOTATION-TARGET",
                    "Use-site targets are not allowed on for-loop variable annotations.",
                    range: range
                )
            }
            loopVariableAnnotations.append(parsed.annotation)
            index += parsed.nextIndex
        }

        var loopVariable: InternedString?
        var loopVariableTypeRef: TypeRefID?
        if let token = current(),
           token.kind != .keyword(.in),
           let name = tokenText(token)
        {
            loopVariable = name
            _ = consume()
            if consumeIf(.symbol(.colon)) != nil {
                if let following = current(),
                   following.kind == .keyword(.in) || following.kind == .symbol(.rParen)
                {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0020",
                        "Expected type after ':'.",
                        range: following.range
                    )
                } else {
                    // Capture the declared loop-variable type (e.g. `c: Int`)
                    // so sema can check it against the iterator element type.
                    var typeTokens: [Token] = []
                    var typeDepth = 0
                    while let typeToken = current() {
                        if typeToken.kind == .keyword(.in) { break }
                        if typeToken.kind == .symbol(.rParen), typeDepth == 0 { break }
                        switch typeToken.kind {
                        case .symbol(.lParen), .symbol(.lBracket), .symbol(.lessThan):
                            typeDepth += 1
                        case .symbol(.rParen), .symbol(.rBracket), .symbol(.greaterThan), .symbol(.greaterOrEqual):
                            typeDepth -= 1
                        default:
                            break
                        }
                        typeTokens.append(typeToken)
                        _ = consume()
                    }
                    if !typeTokens.isEmpty,
                       let parsed = TypeRefParserCore.parseTypeRefPrefix(
                           typeTokens[...],
                           interner: interner,
                           astArena: astArena,
                           options: .declaration,
                           diagnostics: diagnostics,
                           recursionDepth: recursionDepth
                       )
                    {
                        loopVariableTypeRef = parsed.ref
                    }
                }
            }
        }

        var groupDepth = 0
        while let token = current() {
            if token.kind == .keyword(.in) { break }
            if token.kind == .symbol(.rParen), groupDepth == 0 { break }
            switch token.kind {
            case .symbol(.lParen), .symbol(.lBracket), .symbol(.lessThan):
                groupDepth += 1
            case .symbol(.rParen), .symbol(.rBracket), .symbol(.greaterThan), .symbol(.greaterOrEqual):
                groupDepth -= 1
            case .symbol(.comma) where groupDepth == 0:
                diagnostics?.error(
                    "KSWIFTK-PARSE-0004",
                    "Unexpected ',' in 'for' loop header.",
                    range: token.range
                )
            default:
                break
            }
            _ = consume()
        }
        if consumeIf(.keyword(.in)) == nil {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected 'in' in 'for' loop header.",
                range: current()?.range ?? forToken.range
            )
            return nil
        }

        guard let iterable = parseExpression(minPrecedence: 0) else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0001",
                "Expected expression.",
                range: current()?.range ?? forToken.range
            )
            return nil
        }
        // The iterable is an expression: `for (i in x = 1..3)` must not
        // silently drop the assignment and iterate the bare `x`.
        diagnoseAssignmentOperatorAfterExpression()
        if consumeIf(.symbol(.rParen)) == nil {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected ')' after 'for' loop header.",
                range: current()?.range ?? forToken.range
            )
        }

        guard let body = parseControlFlowBodyExpression() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected loop body after 'for' header.",
                range: current()?.range ?? forToken.range
            )
            return nil
        }
        recordStrayElseIfPresent()
        let end = astArena.exprRange(body)?.end ?? forToken.range.end
        let range = SourceRange(start: start ?? forToken.range.start, end: end)
        let exprID = astArena.appendExpr(.forExpr(loopVariable: loopVariable, iterable: iterable, body: body, label: label, range: range))
        if !loopVariableAnnotations.isEmpty {
            // The loop variable is represented by its enclosing forExpr in the
            // current AST model, so retain its annotations there. Sema's
            // expression-annotation pass then validates and applies @Suppress.
            astArena.prependExpressionAnnotations(loopVariableAnnotations, for: exprID)
        }
        if let loopVariableTypeRef {
            astArena.setForVariableTypeRef(loopVariableTypeRef, for: exprID)
        }
        return exprID
    }

    func parseWhileExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let whileToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected parenthesized condition after 'while'.",
                range: current()?.range ?? whileToken.range
            )
            return nil
        }
        guard let condition = parseRequiredControlFlowCondition() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0001",
                "Expected expression.",
                range: current()?.range ?? whileToken.range
            )
            return nil
        }
        diagnoseAssignmentOperatorAfterExpression()
        if consumeIf(.symbol(.rParen)) == nil {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected ')' after 'while' condition.",
                range: current()?.range ?? whileToken.range
            )
        }
        guard let body = parseControlFlowBodyExpression() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected loop body after 'while' condition.",
                range: current()?.range ?? whileToken.range
            )
            return nil
        }
        recordStrayElseIfPresent()
        let end = astArena.exprRange(body)?.end ?? whileToken.range.end
        let range = SourceRange(start: start ?? whileToken.range.start, end: end)
        return astArena.appendExpr(.whileExpr(condition: condition, body: body, label: label, range: range))
    }

    func parseDoWhileExpression(label: InternedString? = nil, start: SourceLocation? = nil) -> ExprID? {
        guard let doToken = consume() else {
            return nil
        }
        let bodyStartIndex = index
        let bodyStartsWithBrace = matches(.symbol(.lBrace))

        // In `do while (condition);`, the condition keyword immediately
        // follows `do`; parsing it as a nested while expression would lose
        // the do-while loop and skip its condition entirely.
        var body: ExprID?
        if matches(.keyword(.while)) {
            let emptyRange = SourceRange(start: doToken.range.end, end: doToken.range.end)
            body = astArena.appendExpr(.blockExpr(statements: [], trailingExpr: nil, range: emptyRange))
        } else {
            body = parseControlFlowBodyExpression()
        }

        if !matches(.keyword(.while)),
           let whileIndex = findDoWhileConditionKeyword(startingAt: bodyStartIndex),
           bodyStartIndex < whileIndex
        {
            let bodyTokens = tokens[bodyStartIndex ..< whileIndex]
            if let reparsedBody = parseDoWhileBodyExpression(from: bodyTokens) {
                body = reparsedBody
                index = whileIndex
            }
        }

        // A braced body already has the correct block/lambda structure from
        // parseControlFlowBodyExpression. Reparsing it recursively duplicates
        // every nested do-while body and makes deeply nested input exponential.
        if !bodyStartsWithBrace, body != nil, bodyStartIndex < index {
            let consumedBodyTokens = tokens[bodyStartIndex ..< index]
            if let normalizedBody = parseDoWhileBodyExpression(from: consumedBodyTokens) {
                body = normalizedBody
            }
        }

        guard let body else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected 'do' block body.",
                range: current()?.range ?? doToken.range
            )
            return nil
        }
        guard matches(.keyword(.while)) else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected 'while' after 'do' block.",
                range: current()?.range ?? doToken.range
            )
            return nil
        }
        _ = consume()
        guard consumeIf(.symbol(.lParen)) != nil else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected parenthesized condition after 'while'.",
                range: current()?.range ?? doToken.range
            )
            return nil
        }
        guard let condition = parseRequiredControlFlowCondition() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0001",
                "Expected expression.",
                range: current()?.range ?? doToken.range
            )
            return nil
        }
        diagnoseAssignmentOperatorAfterExpression()
        if consumeIf(.symbol(.rParen)) == nil {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected ')' after 'while' condition.",
                range: current()?.range ?? doToken.range
            )
        }
        recordStrayElseIfPresent()
        let end = astArena.exprRange(condition)?.end ?? astArena.exprRange(body)?.end ?? doToken.range.end
        let range = SourceRange(start: start ?? doToken.range.start, end: end)
        return astArena.appendExpr(.doWhileExpr(body: body, condition: condition, label: label, range: range))
    }

    private func parseDoWhileBodyExpression(from bodyTokens: ArraySlice<Token>) -> ExprID? {
        // When the body is a braced block, parse it as-is so that semicolons
        // are preserved for intra-block statement splitting.
        if let first = bodyTokens.first, first.kind == .symbol(.lBrace) {
            return BuildASTPhase.ExpressionParser(
                tokens: bodyTokens, interner: interner, astArena: astArena,
                diagnostics: diagnostics
            ).parseBlockExpression()
        }
        let sanitized = bodyTokens.filter { $0.kind != .symbol(.semicolon) }
        guard !sanitized.isEmpty else {
            return nil
        }
        if let localDecl = parseLocalDeclFromSlice(sanitized[...]) {
            return localDecl
        }
        if let localAssign = parseLocalAssignFromSlice(sanitized[...]) {
            return localAssign
        }
        return BuildASTPhase.ExpressionParser(
            tokens: sanitized[...], interner: interner, astArena: astArena,
            diagnostics: diagnostics
        ).parse()
    }

    private func findDoWhileConditionKeyword(startingAt startIndex: Int) -> Int? {
        var scan = startIndex
        var depth = BuildASTPhase.BracketDepth()
        var sawBodyToken = false
        while scan < tokens.endIndex {
            let token = tokens[scan]
            if token.kind == .keyword(.while), depth.isAtTopLevel, sawBodyToken {
                return scan
            }
            depth.track(token.kind)
            sawBodyToken = true
            scan += 1
        }
        return nil
    }

    func parseIfExpression() -> ExprID? {
        guard let ifToken = consume() else {
            return nil
        }
        guard consumeIf(.symbol(.lParen)) != nil else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected parenthesized condition after 'if'.",
                range: current()?.range ?? ifToken.range
            )
            return nil
        }
        guard let condition = parseRequiredControlFlowCondition() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0001",
                "Expected expression.",
                range: current()?.range ?? ifToken.range
            )
            return nil
        }
        diagnoseAssignmentOperatorAfterExpression()
        if consumeIf(.symbol(.rParen)) == nil {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected ')' after 'if' condition.",
                range: current()?.range ?? ifToken.range
            )
        }

        guard let thenExpr = parseControlFlowBodyExpression() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0004",
                "Expected then branch after 'if' condition.",
                range: current()?.range ?? ifToken.range
            )
            return nil
        }

        var elseExpr: ExprID?
        if matches(.symbol(.semicolon)), peek(1)?.kind == .keyword(.else) {
            _ = consume()
        }
        if matches(.keyword(.else)) {
            strayElseToken = nil
            let elseToken = consume()!
            elseExpr = parseControlFlowBodyExpression()
            if elseExpr == nil {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0004",
                    "Expected branch after 'else'.",
                    range: current()?.range ?? elseToken.range
                )
            }
        }
        recordStrayElseIfPresent()

        let end = elseExpr
            .flatMap { astArena.exprRange($0)?.end }
            ?? astArena.exprRange(thenExpr)?.end
            ?? ifToken.range.end
        let range = SourceRange(start: ifToken.range.start, end: end)
        return astArena.appendExpr(.ifExpr(condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, range: range))
    }

    func parseTryExpression() -> ExprID? {
        guard let tryToken = consume() else {
            return nil
        }
        guard let bodyExpr = parseControlFlowBodyExpression() else {
            return nil
        }

        // Nested expressions can bypass the structured CST parser. Use the
        // same range and diagnostic so reparsing a CST error reports it once.
        let nextIsHandler = (matches(.keyword(.catch)) || matches(.keyword(.finally)))
            && peek(1)?.kind != .symbol(.at)
        if !nextIsHandler {
            diagnostics?.error(
                "KSWIFTK-PARSE-0016",
                "Expected 'catch' or 'finally' after 'try' block.",
                range: tryToken.range
            )
        }

        var catchClauses: [CatchClause] = []
        while matches(.keyword(.catch)), peek(1)?.kind != .symbol(.at) {
            let catchToken = consume()!
            let (paramName, paramType) = parseCatchParameter()
            if let catchExpr = parseControlFlowBodyExpression() {
                let clauseEnd = astArena.exprRange(catchExpr)?.end ?? catchToken.range.end
                let clauseRange = SourceRange(start: catchToken.range.start, end: clauseEnd)
                catchClauses.append(CatchClause(paramName: paramName, paramType: paramType, body: catchExpr, range: clauseRange))
            } else {
                break
            }
        }

        var finallyExpr: ExprID?
        if matches(.keyword(.finally)), peek(1)?.kind != .symbol(.at) {
            _ = consume()
            finallyExpr = parseControlFlowBodyExpression()
        }

        let tailEnd = finallyExpr
            .flatMap { astArena.exprRange($0)?.end }
            ?? catchClauses.last.flatMap { astArena.exprRange($0.body)?.end }
            ?? astArena.exprRange(bodyExpr)?.end
            ?? tryToken.range.end
        let range = SourceRange(start: tryToken.range.start, end: tailEnd)
        return astArena.appendExpr(.tryExpr(body: bodyExpr, catchClauses: catchClauses, finallyExpr: finallyExpr, range: range))
    }

    func parseCatchParameter() -> (paramName: InternedString?, paramType: TypeRefID?) {
        guard matches(.symbol(.lParen)) else {
            let fallback = index > tokens.startIndex ? tokens[index - 1].range : tokens.first?.range
            guard let range = current()?.range ?? fallback else {
                return (nil, nil)
            }
            diagnostics?.error(
                "KSWIFTK-PARSE-0028",
                "Expected exception variable declaration after 'catch'.",
                range: range
            )
            return (nil, nil)
        }
        let lParen = consume()!
        while matches(.symbol(.at)) {
            let remaining = Array(tokens[index...])
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: remaining, start: 0, interner: interner, allowUseSiteTarget: false
            ), parsed.nextIndex > 0 else {
                break
            }
            index += parsed.nextIndex
        }
        var paramName: InternedString?
        var paramType: TypeRefID?
        if case let .identifier(name) = current()?.kind {
            paramName = name
            _ = consume()
            if matches(.symbol(.colon)) {
                let colonToken = consume()!
                paramType = parseTypeReference(colonToken.range)
                if paramType == nil {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0020",
                        "Expected type after ':'.",
                        range: current()?.range ?? colonToken.range
                    )
                }
            } else {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0028",
                    "Expected ':' and exception type after catch parameter name.",
                    range: current()?.range ?? lParen.range
                )
            }
        } else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0028",
                "Expected exception variable declaration.",
                range: current()?.range ?? lParen.range
            )
        }
        if !matches(.symbol(.rParen)) {
            diagnostics?.error(
                "KSWIFTK-PARSE-0028",
                "Expected ')' after catch parameter.",
                range: current()?.range ?? lParen.range
            )
        }
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
        return (paramName, paramType)
    }
}
