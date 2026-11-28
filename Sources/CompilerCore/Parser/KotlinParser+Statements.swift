extension KotlinParser {
    func parseBlock(isClassBody: Bool = false) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: true, kind: .block)
        }
        defer { leaveNesting() }

        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        // The first token after `{` is treated as if it has a leading newline,
        // because `{` acts as a statement separator in Kotlin.  This allows
        // single-line class/interface bodies like `interface I { fun f(): T }`
        // to parse the member function as a declaration node.
        var atBlockStart = true
        var closed = false

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                closed = true
                break
            }
            if isLabelStart {
                children.append(.node(parseStatement(inBlock: true)))
                atBlockStart = false
                continue
            }
            // `constructor` is a soft keyword: in executable blocks it is an
            // ordinary name, and its call must survive into the expression AST.
            if isClassBody,
               token.kind == .keyword(.constructor) || token.kind == .softKeyword(.constructor)
            {
                children.append(.node(parseConstructorDeclaration()))
                atBlockStart = false
                continue
            }
            // A `;` is an explicit statement separator, so a declaration-start
            // token right after one is always a fresh declaration — even when
            // it shares a physical line with the statement that preceded the
            // `;` (e.g. `val y = 1; @Anno constructor() : this(0)`).
            // A `}` closing a block-bodied member (class/object/fun body) also
            // self-terminates the declaration in Kotlin, so a same-line
            // declaration after it is valid (e.g. `class A { class B { } class C }`).
            let precededBySemicolon = lastConsumedToken?.kind == .symbol(.semicolon)
            let precededByBlockClose = lastConsumedToken?.kind == .symbol(.rBrace)
            let startsCompanionMember = isClassBody && token.kind == .keyword(.companion)
                && stream.peek(1).kind == .keyword(.object)
            let hasDeclarationPrefix: Bool
            if token.kind == .softKeyword(.context)
                || (!isClassBody && token.kind == .symbol(.at))
            {
                hasDeclarationPrefix = declarationPrefixVerdict(at: 0) == .declaration
            } else {
                hasDeclarationPrefix = true
            }
            let isAnonymousFunction = isAnonymousFunctionExpressionStart()
            if isDeclarationStart(token.kind), hasDeclarationPrefix, !LeanParser.isObjectExpressionStart(self),
               !isAnonymousFunction,
               hasLeadingNewline(token) || atBlockStart || precededBySemicolon || precededByBlockClose || startsCompanionMember
            {
                children.append(.node(parseDeclaration(isLocal: !isClassBody)))
                atBlockStart = false
            } else if !shouldStopStatementBefore(token, inBlock: true) {
                children.append(.node(parseStatement(inBlock: true)))
                atBlockStart = false
            } else {
                let before = stream.index
                skipToSynchronizationPoint(inBlock: true, into: &children, range: &range)
                if stream.index == before, !stream.atEOF() {
                    _ = consumeToken(into: &children, range: &range)
                }
                atBlockStart = false
            }
        }

        if !closed {
            reportUnclosedBlock(lastRange: range.value)
        }
        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    func reportUnclosedBlock(lastRange: SourceRange?) {
        diagnostics.error(
            "KSWIFTK-PARSE-0026",
            "Expected '}' to close block.",
            range: lastRange.map { SourceRange(start: $0.end, end: $0.end) } ?? invalidRange
        )
    }

    func parseStatement(inBlock: Bool) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: inBlock)
        }
        defer { leaveNesting() }

        if LeanParser.isLoopStart(self, kind: stream.peek().kind) {
            return parseLoopStatement(inBlock: inBlock)
        }

        switch stream.peek().kind {
        case .keyword(.if):
            return parseIfStatement(inBlock: inBlock)
        case .keyword(.when):
            return parseWhenStatement(inBlock: inBlock)
        case .keyword(.try):
            return parseTryStatement(inBlock: inBlock)
        default:
            break
        }

        let leadingKind = classifyStatementLeadingToken(stream.peek())
        let isInitializerBlock = inBlock
            && stream.peek().kind == .softKeyword(.`init`)
            && stream.peek(1).kind == .symbol(.lBrace)

        let startCount = stream.index
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = BracketDepth()
        // Whether this statement's own flat tokens (not a nested block's) have
        // included an `if` or `try` keyword. A newline-leading `else` /
        // `catch` / `finally` only continues *this* statement when one did —
        // otherwise it is indistinguishable from the start of an unrelated
        // construct that merely follows on the next line (most notably a
        // subject-less `when`'s next branch: `x > 0 -> 1` has no `if`/`try`,
        // so its own trailing `else ->` must end this statement, not extend
        // it, matching `return if (a) b\nelse c`, which does have one).
        var sawIfOrTryKeyword = false

        while !stream.atEOF() {
            let token = stream.peek()
            if inBlock,
               !children.isEmpty,
               depth.paren == 0,
               depth.bracket == 0,
               depth.template == 0,
               hasLeadingNewline(token),
               LeanParser.shouldSplitStatementOnNewline(token, diagnostics: diagnostics)
            {
                let checksContinuation = if case .symbol = token.kind {
                    true
                } else {
                    sawIfOrTryKeyword && !isLabelStart
                }
                if !(checksContinuation && LeanParser.continuesExpressionBeforeNewline(token, diagnostics: diagnostics)),
                   !endsWithPendingInfixOperator(children),
                   !endsWithControlFlowCondition(children),
                   !(consumedTokensEndWithContextClause(children) && isAnonymousFunctionExpressionStart())
                {
                    break
                }
            }
            // An `if`/`try` inside a `${ ... }` template arms `else`-like
            // continuations only for the template's own expression, never
            // for the statement that follows the closing `}`.
            if depth.template == 0 {
                if case .keyword(.if) = token.kind {
                    sawIfOrTryKeyword = true
                } else if case .keyword(.try) = token.kind {
                    sawIfOrTryKeyword = true
                }
            }
            let closesTopLevelExpressionBrace: Bool = if case .symbol(.rBrace) = token.kind {
                !inBlock && depth.brace > 0
            } else {
                false
            }
            if depth.template == 0,
               shouldStopStatementBefore(token, inBlock: inBlock), !closesTopLevelExpressionBrace {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                let blockID = LeanParser.consumedTokensEndWithWhenSubject(self, children: children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock()
                children.append(.node(blockID))
                if isInitializerBlock {
                    if case .symbol(.semicolon) = stream.peek().kind {
                        _ = consumeToken(into: &children, range: &range)
                    }
                    break
                }
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            depth.track(token.kind)
            if case .symbol(.semicolon) = token.kind {
                break
            }
            if !inBlock, depth.template == 0, hasLeadingNewline(stream.peek()) {
                break
            }
        }

        if stream.index == startCount, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }

        let nodeKind = resolveStatementKind(leadingKind, children: children)

        return arena.appendNode(
            kind: nodeKind,
            range: range.value ?? invalidRange, children
        )
    }

    func parseIfStatement(inBlock: Bool) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: inBlock)
        }
        defer { leaveNesting() }

        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        _ = consumeToken(into: &children, range: &range)

        if case .symbol(.lParen) = stream.peek().kind {
            let conditionGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
            children.append(.node(conditionGroup))
            range.append(arena.node(conditionGroup).range)
        } else {
            diagnostics.error(
                "KSWIFTK-PARSE-0004",
                "Expected parenthesized condition after 'if'.",
                range: stream.peek().rangeIfAvailable
            )
        }

        let thenBranchStart = stream.index
        appendBranchBody(inBlock: inBlock, into: &children, range: &range, stopBeforeElse: true)
        if stream.index == thenBranchStart {
            diagnostics.error(
                "KSWIFTK-PARSE-0004",
                "Expected then branch after 'if' condition.",
                range: stream.peek().rangeIfAvailable
            )
        }

        if case .keyword(.else) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            let elseBranchStart = stream.index
            appendBranchBody(inBlock: inBlock, into: &children, range: &range, stopBeforeElse: false)
            if stream.index == elseBranchStart {
                diagnostics.error(
                    "KSWIFTK-PARSE-0004",
                    "Expected branch after 'else'.",
                    range: stream.peek().rangeIfAvailable
                )
            }
        }

        return arena.appendNode(kind: .ifExpr, range: range.value ?? invalidRange, children)
    }

    func parseWhenStatement(inBlock: Bool) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: inBlock)
        }
        defer { leaveNesting() }

        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        _ = consumeToken(into: &children, range: &range)

        if case .symbol(.lParen) = stream.peek().kind {
            let subjectGroup = parseBalancedGroup(
                opening: .lParen, closing: .rParen, allowsWhenSubjectVariable: true
            )
            children.append(.node(subjectGroup))
            range.append(arena.node(subjectGroup).range)
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseWhenBody(inBlock: inBlock)
            children.append(.node(body))
            range.append(arena.node(body).range)
        }

        return arena.appendNode(kind: .whenExpr, range: range.value ?? invalidRange, children)
    }

    func parseTryStatement(inBlock: Bool) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: inBlock)
        }
        defer { leaveNesting() }

        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        let tryToken = consumeToken(into: &children, range: &range)

        appendTryBody(inBlock: inBlock, into: &children, range: &range)

        let nextIsHandler = !isLabelStart
            && (stream.peek().kind == .keyword(.catch) || stream.peek().kind == .keyword(.finally))
        if !nextIsHandler {
            diagnostics.error(
                "KSWIFTK-PARSE-0016",
                "Expected 'catch' or 'finally' after 'try' block.",
                range: tryToken.range
            )
        }

        while case .keyword(.catch) = stream.peek().kind, !isLabelStart {
            _ = consumeToken(into: &children, range: &range)
            if case .symbol(.lParen) = stream.peek().kind {
                let paramGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
                children.append(.node(paramGroup))
                range.append(arena.node(paramGroup).range)
            }
            appendTryBody(inBlock: inBlock, into: &children, range: &range)
        }

        if case .keyword(.finally) = stream.peek().kind, !isLabelStart {
            _ = consumeToken(into: &children, range: &range)
            appendTryBody(inBlock: inBlock, into: &children, range: &range)
        }

        return arena.appendNode(kind: .tryExpr, range: range.value ?? invalidRange, children)
    }

    func appendBranchBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool
    ) {
        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: stopBeforeElse,
            stopBeforeCatchFinally: false,
            stopBeforeTopLevelComma: false
        )
    }

    func appendTryBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: false,
            stopBeforeCatchFinally: true,
            stopBeforeTopLevelComma: false
        )
    }

    private func appendControlFlowBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool,
        stopBeforeCatchFinally: Bool,
        stopBeforeTopLevelComma: Bool
    ) {
        let token = stream.peek()
        switch token.kind {
        case .symbol(.lBrace):
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
        case .keyword(.if):
            let node = parseIfStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.when):
            let node = parseWhenStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.try):
            let node = parseTryStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        case .keyword(.for), .keyword(.while), .keyword(.do):
            let node = parseLoopStatement(inBlock: inBlock)
            children.append(.node(node))
            range.append(arena.node(node).range)
        default:
            consumeInlineBody(
                inBlock: inBlock,
                into: &children,
                range: &range,
                stopBeforeElse: stopBeforeElse,
                stopBeforeCatchFinally: stopBeforeCatchFinally,
                stopBeforeTopLevelComma: stopBeforeTopLevelComma
            )
        }
    }

    func consumeInlineBody(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        stopBeforeElse: Bool,
        stopBeforeCatchFinally: Bool,
        stopBeforeTopLevelComma: Bool
    ) {
        var depth = BracketDepth()
        let startChildCount = children.count
        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = depth.isTopLevel
            // `atBodyBoundary` is the top level *outside* any `${ ... }`
            // template: `else`/`catch`/`finally`/`,`/newline inside a template
            // belong to the template's own expression and never end this body.
            let atBodyBoundary = atTopLevel && depth.template == 0
            if atBodyBoundary, shouldStopStatementBefore(token, inBlock: inBlock) { break }
            if stopBeforeElse, atBodyBoundary,
               token.kind == .keyword(.else) { break }
            if stopBeforeTopLevelComma, atBodyBoundary,
               token.kind == .symbol(.comma) { break }
            if stopBeforeCatchFinally, atBodyBoundary {
                if case .keyword(.catch) = token.kind { break }
                if case .keyword(.finally) = token.kind { break }
            }
            if inBlock,
               children.count > startChildCount,
               atBodyBoundary,
               hasLeadingNewline(token),
               LeanParser.shouldSplitStatementOnNewline(token, diagnostics: diagnostics),
               !(consumedTokensEndWithContextClause(children) && isAnonymousFunctionExpressionStart())
            {
                break
            }

            if case .symbol(.lBrace) = token.kind, inBlock, atTopLevel {
                let block = LeanParser.consumedTokensEndWithWhenSubject(self, children: children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock()
                children.append(.node(block))
                range.append(arena.node(block).range)
                continue
            }

            _ = consumeToken(into: &children, range: &range)
            depth.track(token.kind)
            // Outside a block, braces are consumed flat, so a `;` inside a
            // lambda body (`0 -> run { a(); b }`) must not end the entry.
            if token.kind == .symbol(.semicolon), atBodyBoundary { return }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                let stillGrouped = !depth.isTopLevel || depth.template > 0
                if stillGrouped {
                    continue
                }
                // Only symbol continuations here: a newline-leading `else` /
                // `catch` / `finally` belongs to the enclosing control-flow
                // statement, which consumes it itself.
                let next = stream.peek()
                if case .symbol = next.kind,
                   LeanParser.continuesExpressionBeforeNewline(next, diagnostics: diagnostics)
                {
                    continue
                }
                if endsWithPendingInfixOperator(children) {
                    continue
                }
                break
            }
        }
    }

    private func parseWhenBody(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            if token.kind == .symbol(.semicolon) || token.kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
                continue
            }

            let entry = parseWhenEntry(inBlock: inBlock)
            children.append(.node(entry))
            range.append(arena.node(entry).range)

            while stream.peek().kind == .symbol(.semicolon) || stream.peek().kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
            }
        }

        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    private func parseWhenEntry(inBlock: Bool) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        if stream.peek().kind == .keyword(.else) {
            _ = consumeToken(into: &children, range: &range)
            // Kotlin 2.1 when guards: `else if <guard> ->` is a fallible
            // catch-all branch, not the final else — parse the guard like a
            // branch condition so the `->` terminates the entry normally.
            if stream.peek().kind == .keyword(.if) {
                let guardCondition = parseWhenConditionList()
                children.append(.node(guardCondition))
                range.append(arena.node(guardCondition).range)
            }
        } else {
            let conditionList = parseWhenConditionList()
            children.append(.node(conditionList))
            range.append(arena.node(conditionList).range)
        }

        consumeIf(
            expected: .symbol(.arrow),
            into: &children,
            range: &range,
            code: "KSWIFTK-PARSE-0010"
        )

        appendControlFlowBody(
            inBlock: inBlock,
            into: &children,
            range: &range,
            stopBeforeElse: false,
            stopBeforeCatchFinally: false,
            stopBeforeTopLevelComma: true
        )

        return arena.appendNode(kind: .whenEntry, range: range.value ?? invalidRange, children)
    }

    private func parseWhenConditionList() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .symbol(.arrow) || token.kind == .symbol(.rBrace) {
                break
            }

            let condition = parseWhenCondition()
            children.append(.node(condition))
            range.append(arena.node(condition).range)

            if stream.peek().kind == .symbol(.comma) {
                _ = consumeToken(into: &children, range: &range)
                if stream.peek().kind == .symbol(.arrow) {
                    break
                }
                continue
            }
            break
        }

        return arena.appendNode(kind: .whenConditionList, range: range.value ?? invalidRange, children)
    }

    private func consumedTokensEndWithContextClause(_ children: [SyntaxChild]) -> Bool {
        var flatTokens: [Token] = []
        for child in children {
            guard case let .token(tokenID) = child, let token = arena.token(tokenID) else {
                flatTokens.removeAll()
                continue
            }
            flatTokens.append(token)
        }
        guard flatTokens.last?.kind == .symbol(.rParen) else {
            return false
        }

        var depth = 0
        var index = flatTokens.count - 1
        while index >= 0 {
            switch flatTokens[index].kind {
            case .symbol(.rParen):
                depth += 1
            case .symbol(.lParen):
                depth -= 1
                if depth == 0 {
                    guard index > 0,
                          flatTokens[index - 1].kind == .softKeyword(.context)
                    else {
                        return false
                    }
                    if index > 1,
                       flatTokens[index - 2].kind == .symbol(.dot)
                        || flatTokens[index - 2].kind == .symbol(.questionDot)
                    {
                        return false
                    }
                    return true
                }
            default:
                break
            }
            index -= 1
        }
        return false
    }

    private func parseWhenCondition() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = BracketDepth()

        while !stream.atEOF() {
            let token = stream.peek()
            if depth.paren == 0, depth.bracket == 0, depth.brace == 0, depth.template == 0 {
                if token.kind == .symbol(.comma) || token.kind == .symbol(.arrow) || token.kind == .symbol(.rBrace) {
                    break
                }
                // A leading-newline `if` continues the condition as a Kotlin
                // 2.1 branch guard (`is T\nif cond ->`), as does the guard
                // operand after `if` itself (`is T if\ncond ->`) or a pending
                // infix operator (`cond if a &&\nb ->`). A token that can only
                // continue the condition expression — `.`/`?.`/`!!`, `is`/`in`/
                // `as`, `!is`/`!in`, `?:`/`&&`/`||` — also keeps the entry
                // going (`x\n.isEmpty ->`, `a &&\nb ->`); only a token that
                // could start a fresh entry ends the condition here.
                if hasLeadingNewline(token), !children.isEmpty,
                   token.kind != .keyword(.if),
                   lastConsumedToken?.kind != .keyword(.if),
                   !endsWithPendingInfixOperator(children),
                   !LeanParser.whenConditionContinuesAfterLineBreak(self)
                {
                    break
                }
            }

            _ = consumeToken(into: &children, range: &range)
            depth.track(token.kind)
        }

        if children.isEmpty {
            insertMissingToken(
                expected: .identifier(.invalid),
                into: &children,
                range: &range,
                code: "KSWIFTK-PARSE-0011",
                message: "Expected when branch condition."
            )
        }

        return arena.appendNode(kind: .whenCondition, range: range.value ?? invalidRange, children)
    }

    func classifyStatementLeadingToken(_ token: Token) -> SyntaxKind {
        switch token.kind {
        case .keyword(.if):
            .ifExpr
        case .keyword(.when):
            .whenExpr
        case .keyword(.try):
            .tryExpr
        case .identifier, .backtickedIdentifier:
            .callExpr
        case .softKeyword:
            .callExpr
        default:
            .statement
        }
    }

    func resolveStatementKind(_ candidate: SyntaxKind, children: [SyntaxChild]) -> SyntaxKind {
        switch candidate {
        case .ifExpr, .whenExpr, .tryExpr:
            return candidate
        case .callExpr:
            for child in children {
                if case let .node(childID) = child,
                   arena.node(childID).kind == .block
                {
                    return .callExpr
                }
                if case let .token(tokenID) = child,
                   let token = arena.token(tokenID),
                   token.kind == .symbol(.lParen)
                {
                    return .callExpr
                }
            }
            return .statement
        default:
            return .statement
        }
    }

    func parseLoopStatement(inBlock: Bool) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: inBlock)
        }
        defer { leaveNesting() }

        _ = inBlock
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        let loopToken = consumeToken(into: &children, range: &range)

        switch loopToken.kind {
        case .keyword(.for), .keyword(.while):
            if case .symbol(.lParen) = stream.peek().kind {
                if case .keyword(.for) = loopToken.kind {
                    let modifier = stream.peek(1)
                    if modifier.kind == .keyword(.val) || modifier.kind == .keyword(.var) {
                        diagnostics.error(
                            "KSWIFTK-PARSE-0021",
                            "A for-loop variable cannot be declared with 'val' or 'var'.",
                            range: modifier.range
                        )
                    }
                }
                let header = parseBalancedGroup(opening: .lParen, closing: .rParen)
                children.append(.node(header))
                range.append(arena.node(header).range)
            }
            appendLoopBody(into: &children, range: &range)

        case .keyword(.do):
            appendDoWhileBody(into: &children, range: &range)
            if case .keyword(.while) = stream.peek().kind {
                _ = consumeToken(into: &children, range: &range)
                if case .symbol(.lParen) = stream.peek().kind {
                    let condition = parseBalancedGroup(opening: .lParen, closing: .rParen)
                    children.append(.node(condition))
                    range.append(arena.node(condition).range)
                }
            }

        default:
            break
        }

        return arena.appendNode(kind: .loopStmt, range: range.value ?? invalidRange, children)
    }

    func appendLoopBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if case .symbol(.lBrace) = stream.peek().kind {
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
            return
        }
        let before = stream.index
        let body = parseStatement(inBlock: true)
        children.append(.node(body))
        range.append(arena.node(body).range)
        if stream.index == before, !stream.atEOF() {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    func appendDoWhileBody(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if case .symbol(.lBrace) = stream.peek().kind {
            let block = parseBlock()
            children.append(.node(block))
            range.append(arena.node(block).range)
            return
        }

        var bodyChildren: [SyntaxChild] = []
        var bodyRange = RangeAccumulator()
        var depth = BracketDepth()

        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = depth.isTopLevel
            if atTopLevel, !bodyChildren.isEmpty,
               token.kind == .keyword(.while)
            {
                break
            }
            if shouldStopStatementBefore(token, inBlock: true) {
                break
            }
            if atTopLevel,
               !bodyChildren.isEmpty,
               hasLeadingNewline(token),
               LeanParser.shouldSplitStatementOnNewline(token, diagnostics: diagnostics)
            {
                break
            }

            _ = consumeToken(into: &bodyChildren, range: &bodyRange)
            depth.track(token.kind)

            if token.kind == .symbol(.semicolon), atTopLevel {
                break
            }
        }

        if bodyChildren.isEmpty {
            let before = stream.index
            let body = parseStatement(inBlock: true)
            children.append(.node(body))
            range.append(arena.node(body).range)
            if stream.index == before, !stream.atEOF() {
                _ = consumeToken(into: &children, range: &range)
            }
            return
        }

        let bodyNode = arena.appendNode(
            kind: .statement,
            range: bodyRange.value ?? invalidRange,
            bodyChildren
        )
        children.append(.node(bodyNode))
        range.append(arena.node(bodyNode).range)
    }

    func isAnonymousFunctionExpressionStart(at offset: Int = 0) -> Bool {
        LeanParser.isAnonymousFunctionExpressionStart(self, at: offset)
    }

    enum DeclarationPrefixVerdict: Equatable {
        case declaration
        case notDeclaration
        case overBudget
    }

    func declarationPrefixVerdict(at offset: Int) -> DeclarationPrefixVerdict {
        LeanParser.declarationPrefixVerdict(self, at: offset)
    }

    func startsGenuineDeclaration(at offset: Int) -> Bool {
        declarationPrefixVerdict(at: offset) != .notDeclaration
    }

    static let declarationLookaheadWorkLimit = 4096

    func reportDeclarationLookaheadBudget(at offset: Int) {
        diagnostics.error(
            "KSWIFTK-PARSE-0007",
            "Declaration prefix exceeds the parser lookahead limit; recovering at this boundary.",
            range: stream.peek(offset).rangeIfAvailable
        )
    }

    func isObjectExpressionStart(_ token: Token) -> Bool {
        LeanParser.isObjectExpressionStart(self)
    }

    func isAmbiguousDeclarationPrefix(_ token: Token) -> Bool {
        LeanParser.isAmbiguousDeclarationPrefix(self, kind: token.kind)
    }

    func consumeDeclarationLookaheadWork(_ work: inout Int, at offset: Int) -> Bool {
        guard work < Self.declarationLookaheadWorkLimit else {
            reportDeclarationLookaheadBudget(at: offset)
            return false
        }
        work += 1
        return true
    }

    func offsetPastBalancedGroup(from offset: Int, maxDistance: Int? = nil) -> Int {
        LeanParser.offsetPastParens(self, from: offset, maxDistance: maxDistance)
    }

    func offsetPastTypeArguments(from offset: Int) -> Int {
        LeanParser.offsetPastTypeArguments(self, from: offset)
    }

    func parseTail(
        inBlock: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator,
        allowsDeclarationAssignment: Bool = false,
        allowsClassHeaderColon: Bool = false,
        allowsClassDelegation: Bool = false,
        allowsWhereClauseContinuation: Bool = false,
        allowsFunctionWhereClause: Bool = false,
        allowsPropertyDelegation: Bool = false,
        allowsDeclaredTypeColon: Bool = false,
        stopsAtFunctionDelegation: Bool = false,
        isClassBody: Bool = false
    ) {
        var progress = false
        var sawAssignment = false
        var sawSupertypeColon = false
        var sawByKeyword = false
        var sawTryKeyword = false
        var functionTypeNameAfterAnnotation = false
        var delegateBraceTracker = DelegateExpressionBraceTracker()
        var depth = BracketDepth()
        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = depth.isTopLevel
                && depth.template == 0
            if allowsPropertyDelegation, atTopLevel, depth.angle == 0, !sawAssignment,
               LeanParser.isExplicitBackingFieldStart(self),
               lastConsumedToken?.kind != .symbol(.dot),
               lastConsumedToken?.kind != .symbol(.questionDot)
            {
                break
            }
            if stopsAtFunctionDelegation, atTopLevel, !sawAssignment {
                let expectsTypeName = functionTypeNameAfterAnnotation || LeanParser.canStartTypeName(self, after: lastConsumedToken?.kind)
                if token.kind == .symbol(.at), expectsTypeName {
                    if case let .complete(end) = LeanParser.annotationPrefixEnd(self, from: 0) {
                        for _ in 0..<end { _ = consumeToken(into: &children, range: &range) }
                        functionTypeNameAfterAnnotation = true
                        progress = true
                        continue
                    }
                }
                // Class members do not require a separator after a bodyless
                // function. Keep a type named `companion` in the signature,
                // but leave a following companion declaration to parseBlock.
                if !expectsTypeName, token.kind == .keyword(.companion), stream.peek(1).kind == .keyword(.object) {
                    return
                }
                functionTypeNameAfterAnnotation = false
            }
            if stopsAtFunctionDelegation,
               atTopLevel,
               !sawAssignment,
               token.kind == .softKeyword(.by),
               !LeanParser.canStartTypeName(self, after: lastConsumedToken?.kind)
            {
                diagnostics.error(
                    "KSWIFTK-PARSE-0006",
                    "Unexpected 'by' after function signature.",
                    range: token.range
                )
                break
            }
            if !inBlock, !children.isEmpty, atTopLevel, hasLeadingNewline(token),
               token.kind == .keyword(.this)
            {
                let continuesAfterPreviousToken = lastConsumedToken.map {
                    LeanParser.continuesExpressionAfterNewline(self, kind: $0.kind)
                } ?? false
                if !continuesAfterPreviousToken,
                   !endsWithPendingInfixOperator(children),
                   !endsWithControlFlowCondition(children)
                {
                    break
                }
            }
            if atTopLevel, token.kind == .symbol(.assign) { sawAssignment = true }
            if atTopLevel, token.kind == .symbol(.colon) { sawSupertypeColon = true }
            if atTopLevel, token.kind == .softKeyword(.by) { sawByKeyword = true }
            if atTopLevel, shouldStopStatementBefore(token, inBlock: inBlock), !LeanParser.isObjectExpressionStart(self),
               LeanParser.isGenuineDeclarationBoundary(self)
            {
                break
            }
            if atTopLevel, token.kind == .symbol(.at), !startsGenuineDeclaration(at: 0) {
                if case let .complete(end) = LeanParser.annotationPrefixEnd(self, from: 0) {
                    for _ in 0..<end { _ = consumeToken(into: &children, range: &range) }
                    progress = true
                    continue
                }
            }
            if case .symbol(.lBrace) = token.kind,
               atTopLevel,
               (allowsClassDelegation && sawSupertypeColon
                   || allowsPropertyDelegation && sawAssignment),
               delegateBraceTracker.braceContinuesDelegateExpression()
            {
                // A brace that belongs to a `by` expression in a class header
                // or object-literal property initializer (`by when (x) { ... }`,
                // `by if (c) { } else { }`, ...) is part of the expression, not
                // the declaration/object body. Keep its tokens with the
                // declaration so AST construction can parse the full expression;
                // a later top-level brace can still start the class or object body.
                let braceToken = consumeToken(into: &children, range: &range)
                delegateBraceTracker.note(braceToken.kind, atTopLevel: true)
                depth.track(token.kind)
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind, inBlock, atTopLevel {
                let blockID = LeanParser.consumedTokensEndWithWhenSubject(self, children: children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock()
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind, atTopLevel {
                let blockID = LeanParser.consumedTokensEndWithWhenSubject(self, children: children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock(isClassBody: isClassBody)
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                if LeanParser.continuesAfterBlock(self, sawTry: sawTryKeyword) {
                    continue
                }
                break
            }
            if case .keyword(.try) = token.kind {
                sawTryKeyword = true
            }
            let consumedToken = consumeToken(into: &children, range: &range)
            progress = true
            delegateBraceTracker.note(consumedToken.kind, atTopLevel: atTopLevel)
            depth.track(token.kind)
            if case .symbol(.semicolon) = token.kind, atTopLevel {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                let stillGrouped = !depth.isTopLevel
                    || depth.template > 0
                if stillGrouped {
                    continue
                }
                if LeanParser.continuesExpressionAfterNewline(self, kind: token.kind)
                    || (allowsFunctionWhereClause && !sawAssignment && token.kind == .softKeyword(.where))
                {
                    if startsGenuineDeclaration(at: 0), !LeanParser.isObjectExpressionStart(self) {
                        break
                    }
                    continue
                }
                if LeanParser.continuesExpressionBeforeNewline(stream.peek(), diagnostics: diagnostics)
                    || (allowsDeclarationAssignment && !sawAssignment && stream.peek().kind == .symbol(.assign))
                    || (allowsPropertyDelegation && !sawAssignment && stream.peek().kind == .softKeyword(.by))
                    || (allowsFunctionWhereClause && !sawAssignment
                        && stream.peek().kind == .softKeyword(.where))
                    || (allowsClassHeaderColon && stream.peek().kind == .symbol(.colon))
                    // A function return type or property type annotation may
                    // also begin on the next line (`fun R.f()\n    : R`).
                    // Once a delegation `by` has been consumed the signature
                    // region is over: a following `:` cannot be a declared
                    // type (`val x by foo()\n    : Int` is rejected by
                    // kotlinc, not absorbed into the delegate expression).
                    // The exception is an `object` literal delegate, whose
                    // own supertype colon may still start on the next line
                    // (`val x by object\n    : D { }`).
                    || (allowsDeclaredTypeColon && !sawAssignment
                        && (!sawByKeyword || lastConsumedToken?.kind == .keyword(.object))
                        && stream.peek().kind == .symbol(.colon))
                    || (allowsClassDelegation && sawSupertypeColon && stream.peek().kind == .softKeyword(.by))
                    || (allowsWhereClauseContinuation && stream.peek().kind == .softKeyword(.where))
                    || endsWithPendingInfixOperator(children)
                    || endsWithControlFlowCondition(children)
                {
                    continue
                }
                if consumedTokensEndWithContextClause(children),
                   isAnonymousFunctionExpressionStart()
                {
                    continue
                }
                break
            }
        }
        if !progress, !shouldStopStatementBefore(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
    }
}
