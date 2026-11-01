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
            // A contextual keyword followed by @ starts a label, not a declaration.
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
            if isDeclarationStart(token.kind), hasDeclarationPrefix, !isObjectExpressionStart(token),
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

        if isLoopStart(stream.peek().kind) {
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
            let canContinueWithElseLikeKeyword = sawIfOrTryKeyword
                && !isLabelStart
                && ParserBoundaryPolicy.continuesExpressionBeforeNewline(token.kind)
            let canContinueWithSymbol: Bool = if case .symbol = token.kind {
                ParserBoundaryPolicy.continuesExpressionBeforeNewline(token.kind)
            } else {
                false
            }
            if inBlock,
               !children.isEmpty,
               depth.paren == 0,
               depth.bracket == 0,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind),
               !canContinueWithSymbol,
               !canContinueWithElseLikeKeyword,
               !endsWithPendingInfixOperator(children),
               !endsWithControlFlowCondition(children)
            {
                break
            }
            if case .keyword(.if) = token.kind {
                sawIfOrTryKeyword = true
            } else if case .keyword(.try) = token.kind {
                sawIfOrTryKeyword = true
            }
            let closesTopLevelExpressionBrace: Bool = if case .symbol(.rBrace) = token.kind {
                !inBlock && depth.brace > 0
            } else {
                false
            }
            if shouldStopStatementBefore(token, inBlock: inBlock), !closesTopLevelExpressionBrace {
                break
            }
            if case .symbol(.lBrace) = token.kind, inBlock {
                let blockID = consumedTokensEndWithWhenSubject(children)
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
            if !inBlock, hasLeadingNewline(stream.peek()) {
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

        // Parse body as a structured when block so branch conditions remain explicit in CST.
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
            if atTopLevel, shouldStopStatementBefore(token, inBlock: inBlock) { break }
            if stopBeforeElse, atTopLevel,
               token.kind == .keyword(.else) { break }
            if stopBeforeTopLevelComma, atTopLevel,
               token.kind == .symbol(.comma) { break }
            if stopBeforeCatchFinally, atTopLevel {
                if case .keyword(.catch) = token.kind { break }
                if case .keyword(.finally) = token.kind { break }
            }
            if inBlock,
               children.count > startChildCount,
               atTopLevel,
               hasLeadingNewline(token),
               shouldSplitStatementOnNewline(token.kind)
            {
                break
            }

            if case .symbol(.lBrace) = token.kind, inBlock, atTopLevel {
                let block = consumedTokensEndWithWhenSubject(children)
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
            if token.kind == .symbol(.semicolon), atTopLevel { return }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                let stillGrouped = !depth.isTopLevel
                if stillGrouped {
                    continue
                }
                // Only symbol continuations here: a newline-leading `else` /
                // `catch` / `finally` belongs to the enclosing control-flow
                // statement, which consumes it itself.
                let nextKind = stream.peek().kind
                if case .symbol = nextKind, ParserBoundaryPolicy.continuesExpressionBeforeNewline(nextKind) {
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

    /// Whether the flat tokens already consumed end in `when` or
    /// `when (subject)`, so a `{` at the current position opens a when body
    /// rather than a plain block or lambda. `when` reached through generic
    /// statement/declaration tails (`= when (x) {`, `return when (x) {`,
    /// `x = when (x) {`) routes here so entries are parsed as when entries —
    /// otherwise a newline-leading `if` (a Kotlin 2.1 branch guard:
    /// `cond\nif g ->`, `else\nif g ->`) would be reclaimed as an if
    /// statement.
    private func consumedTokensEndWithWhenSubject(_ children: [SyntaxChild]) -> Bool {
        var parenDepth = 0
        for child in children.reversed() {
            // Nodes are opaque balanced groups (blocks, balanced parens):
            // their inner parens cannot affect the depth at this level.
            guard case let .token(tokenID) = child, let token = arena.token(tokenID) else {
                continue
            }
            switch token.kind {
            case .symbol(.rParen):
                parenDepth += 1
            case .symbol(.lParen):
                parenDepth -= 1
                if parenDepth < 0 { return false }
            default:
                if parenDepth == 0 {
                    // The first top-level token looking back: `when` means
                    // the trailing `)` closed a `when (…)` subject, or `when`
                    // directly precedes the brace (`when {`).
                    return token.kind == .keyword(.when)
                }
            }
        }
        return false
    }

    private func parseWhenCondition() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = BracketDepth()

        while !stream.atEOF() {
            let token = stream.peek()
            if depth.paren == 0, depth.bracket == 0, depth.brace == 0 {
                if token.kind == .symbol(.comma) || token.kind == .symbol(.arrow) || token.kind == .symbol(.rBrace) {
                    break
                }
                // A leading-newline `if` continues the condition as a Kotlin
                // 2.1 branch guard (`is T\nif cond ->`), as does the guard
                // operand after `if` itself (`is T if\ncond ->`) or a pending
                // infix operator (`cond if a &&\nb ->`); other tokens start a
                // new entry.
                if hasLeadingNewline(token), !children.isEmpty,
                   token.kind != .keyword(.if),
                   lastConsumedToken?.kind != .keyword(.if),
                   !endsWithPendingInfixOperator(children)
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

    /// Keeps the trailing `while (...)` condition outside of the body node.
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
               shouldSplitStatementOnNewline(token.kind)
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

    func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        ParserBoundaryPolicy.shouldSplitStatementOnNewline(kind)
    }

    /// `object` is ambiguous as a bare token: `object Foo : Base { ... }` starts
    /// a new top-level declaration, but `object : Base(x) { ... }` / `object { ... }`
    /// is an anonymous object *expression* continuing the current one (e.g. as the
    /// value of an expression-bodied function's `= object : Base(x) { ... }`,
    /// possibly on its own line). `isDeclarationStart` cannot tell these apart
    /// since it only sees the `object` keyword itself — an identifier following it
    /// means a name is present (named declaration); `:`/`{` immediately after
    /// means there is none (object expression).
    func isObjectExpressionStart(_ token: Token) -> Bool {
        guard case .keyword(.object) = token.kind else {
            return false
        }
        switch stream.peek(1).kind {
        case .symbol(.colon), .symbol(.lBrace):
            return true
        default:
            return false
        }
    }

    func isAnonymousFunctionExpressionStart(at offset: Int = 0) -> Bool {
        guard stream.peek(offset).kind == .keyword(.fun) else { return false }
        var cursor = offset + 1
        var depth = 0
        var prevNonTriviaKind: TokenKind? = .keyword(.fun)
        while cursor < offset + 200 {
            let token = stream.peek(cursor)
            if token.kind == .eof { break }
            switch token.kind {
            case .symbol(.lParen):
                if depth == 0 {
                    if let prev = prevNonTriviaKind {
                        if (prev == .keyword(.fun) || prev == .symbol(.greaterThan)),
                           let nameOffset = offsetAfterParenthesizedReceiver(from: cursor, maxDistance: 4096),
                           isIdentifierLike(stream.peek(nameOffset).kind)
                        {
                            return false
                        }
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
            prevNonTriviaKind = token.kind
            cursor += 1
        }
        return false
    }

    /// A modifier keyword (`suspend`, `private`, ...) or the `context` soft
    /// keyword is ambiguous the same way `object` is (see
    /// `isObjectExpressionStart` above): it can introduce a genuine
    /// declaration (`suspend fun f() {}`, `context(x: T) fun f() {}`) or
    /// appear inside an expression (`suspend { ... }` lambda literal,
    /// `context(...) { ... }` helper call). A single token of lookahead
    /// can't tell these apart.
    func isAmbiguousDeclarationPrefix(_ token: Token) -> Bool {
        switch token.kind {
        case let .keyword(kw):
            return Self.isDeclarationModifierKeyword(kw)
        case .softKeyword(.context):
            return true
        case .symbol(.at):
            return true
        default:
            return false
        }
    }

    enum DeclarationPrefixVerdict: Equatable {
        case declaration
        case notDeclaration
        case overBudget
    }

    /// Memoized for every prefix token visited so expression-tail recovery
    /// does not rescan each suffix of a long chain.
    func declarationPrefixVerdict(at offset: Int) -> DeclarationPrefixVerdict {
        if stream.peek(offset).kind.isLabelName,
           stream.peek(offset + 1).kind == .symbol(.at) {
            return .notDeclaration
        }
        let startIndex = stream.index + offset
        if let cached = genuineDeclarationLookahead[startIndex] {
            return cached ? .declaration : .notDeclaration
        }

        var cursor = offset
        var work = 0
        var prefixIndices: [Int] = []
        var sawValueModifier = false
        while true {
            guard consumeDeclarationLookaheadWork(&work, at: cursor) else {
                // Treat an over-budget prefix as a recovery boundary. The outer
                // parser then consumes it iteratively through normal recovery.
                cacheGenuineDeclarationLookahead(true, for: prefixIndices)
                return .overBudget
            }

            let token = stream.peek(cursor)
            if token.kind == .symbol(.at) {
                prefixIndices.append(stream.index + cursor)
                switch annotationPrefixEnd(from: cursor, work: &work) {
                case let .complete(end):
                    cursor = end
                case .incomplete:
                    cacheGenuineDeclarationLookahead(true, for: prefixIndices)
                    return .declaration
                case .overBudget:
                    cacheGenuineDeclarationLookahead(true, for: prefixIndices)
                    return .overBudget
                }
                continue
            }
            if case let .keyword(kw) = token.kind, Self.isDeclarationModifierKeyword(kw) {
                if kw == .value {
                    sawValueModifier = true
                }
                prefixIndices.append(stream.index + cursor)
                cursor += 1
                continue
            }
            if case .softKeyword(.context) = token.kind {
                prefixIndices.append(stream.index + cursor)
                cursor += 1
                if stream.peek(cursor).kind == .symbol(.lParen) {
                    var depth = 0
                    repeat {
                        guard consumeDeclarationLookaheadWork(&work, at: cursor) else {
                            cacheGenuineDeclarationLookahead(true, for: prefixIndices)
                            return .overBudget
                        }
                        let kind = stream.peek(cursor).kind
                        if kind == .symbol(.lParen) {
                            depth += 1
                        } else if kind == .symbol(.rParen) {
                            depth -= 1
                        } else if kind == .eof {
                            break
                        }
                        cursor += 1
                    } while depth > 0
                }
                continue
            }

            // `value` is a modifier for a value class, but it is also a legal
            // identifier in an expression. In `fun f() =\n value\n fun g() = 0`,
            // the next `fun` is a separate declaration, not one modified by
            // `value`; otherwise `f` loses its expression body.
            let isAnonymousFunction = isAnonymousFunctionExpressionStart(at: cursor)
            let isAnonymousObject = token.kind == .keyword(.object)
                && (stream.peek(cursor + 1).kind == .symbol(.lBrace) || stream.peek(cursor + 1).kind == .symbol(.colon))
            let isCompanionCall = token.kind == .keyword(.companion)
                && stream.peek(cursor + 1).kind == .symbol(.lParen)
            let startsDeclaration = isDeclarationStart(token.kind) && !isAnonymousFunction && !isAnonymousObject && !isCompanionCall
            let result = startsDeclaration
                && (!sawValueModifier || token.kind == .keyword(.class))
            if sawValueModifier, !result {
                // A suffix such as `suspend fun` can still start a declaration
                // after the expression's `value` has been consumed. Do not
                // cache this false verdict for every prefix token.
                genuineDeclarationLookahead[startIndex] = false
            } else {
                cacheGenuineDeclarationLookahead(result, for: prefixIndices)
            }
            // The terminal keyword remains a declaration start on its own,
            // even when this modifier prefix does not belong to it.
            genuineDeclarationLookahead[stream.index + cursor] = startsDeclaration
            return result ? .declaration : .notDeclaration
        }
    }

    func startsGenuineDeclaration(at offset: Int) -> Bool {
        declarationPrefixVerdict(at: offset) != .notDeclaration
    }

    private enum AnnotationPrefixEnd {
        case complete(Int)
        case incomplete
        case overBudget
    }

    /// Bound annotation lookahead before scanning arguments, and preserve the
    /// same declaration synchronization points as parseBalancedGroup.
    private func annotationPrefixEnd(from offset: Int, work: inout Int) -> AnnotationPrefixEnd {
        var cursor = offset + 1
        if isAnnotationUseSiteTarget(stream.peek(cursor)),
           stream.peek(cursor + 1).kind == .symbol(.colon) {
            guard consumeDeclarationLookaheadWork(&work, at: cursor) else { return .overBudget }
            cursor += 2
        }
        guard isIdentifierLike(stream.peek(cursor).kind) else { return .incomplete }
        guard consumeDeclarationLookaheadWork(&work, at: cursor) else { return .overBudget }
        cursor += 1
        while stream.peek(cursor).kind == .symbol(.dot), isIdentifierLike(stream.peek(cursor + 1).kind) {
            guard consumeDeclarationLookaheadWork(&work, at: cursor) else { return .overBudget }
            cursor += 2
        }
        guard stream.peek(cursor).kind == .symbol(.lParen) else { return .complete(cursor) }
        var closingSymbols: [Symbol] = [.rParen]
        cursor += 1
        while !closingSymbols.isEmpty {
            guard consumeDeclarationLookaheadWork(&work, at: cursor) else { return .overBudget }
            let token = stream.peek(cursor)
            if token.kind == .eof { return .incomplete }
            if closingSymbols.count == 1, hasLeadingNewline(token), isAnnotationArgumentRecoveryBoundary(at: cursor) {
                return .incomplete
            }
            if case let .symbol(symbol) = token.kind {
                switch symbol {
                case .lParen: closingSymbols.append(.rParen)
                case .lBracket: closingSymbols.append(.rBracket)
                case .lBrace: closingSymbols.append(.rBrace)
                default:
                    if symbol == closingSymbols.last { closingSymbols.removeLast() }
                }
            }
            cursor += 1
        }
        return .complete(cursor)
    }

    private static let declarationLookaheadWorkLimit = 4096

    func consumeDeclarationLookaheadWork(_ work: inout Int, at offset: Int) -> Bool {
        guard work < Self.declarationLookaheadWorkLimit else {
            let token = stream.peek(offset)
            diagnostics.error(
                "KSWIFTK-PARSE-0007",
                "Declaration prefix exceeds the parser lookahead limit; recovering at this boundary.",
                range: token.rangeIfAvailable
            )
            return false
        }
        work += 1
        return true
    }

    private func cacheGenuineDeclarationLookahead(_ result: Bool, for indices: [Int]) {
        for index in indices {
            genuineDeclarationLookahead[index] = result
        }
    }

    func offsetPastBalancedGroup(
        from offset: Int, open: TokenKind, close: TokenKind, maxDistance: Int? = nil
    ) -> Int {
        var depth = 0
        var index = offset
        repeat {
            if let maxDistance, index - offset >= maxDistance { return offset }
            let kind = stream.peek(index).kind
            if kind == .eof { break }
            if kind == open {
                depth += 1
            } else if kind == close {
                depth -= 1
            }
            index += 1
        } while depth > 0
        return index
    }

    /// Defers to `startsGenuineDeclaration` lookahead only for ambiguous modifier /
    /// `context` prefixes, trusting the caller's own check otherwise.
    private func isGenuineDeclarationBoundary(_ token: Token) -> Bool {
        let isAnonymousFunction = isAnonymousFunctionExpressionStart()
        guard isAmbiguousDeclarationPrefix(token) || isAnonymousFunction else {
            return true
        }
        return startsGenuineDeclaration(at: 0)
    }

    private func isTrailingLambdaOperatorContinuation(_ token: Token) -> Bool {
        guard !hasLeadingNewline(token) else { return false }
        switch token.kind {
        case .keyword(.in):
            return true
        case .symbol(.bang):
            // `!in` and `!is` are the only infix operators that start with `!`.
            let next = stream.peek(1).kind
            return next == .keyword(.in) || next == .keyword(.is)
        case .symbol(.bangBang):
            // `!!` is the not-null postfix operator; it can only apply to the
            // trailing-lambda call here, never start a statement.
            return true
        case .identifier, .backtickedIdentifier:
            return canStartInfixCallArgument(stream.peek(1).kind)
        default:
            return false
        }
    }

    private func canStartInfixCallArgument(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier,
             .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral, .charLiteral,
             .keyword(.true), .keyword(.false), .keyword(.null), .keyword(.if), .keyword(.when),
             .keyword(.try), .keyword(.throw), .keyword(.return), .keyword(.for), .keyword(.while),
             .keyword(.do), .keyword(.super), .keyword(.this), .keyword(.object),
             .symbol(.lParen), .symbol(.lBrace), .symbol(.lBracket), .symbol(.minus), .symbol(.plus),
             .symbol(.bang), .symbol(.doubleColon),
             .stringQuote, .rawStringQuote, .multiDollarStringQuote, .multiDollarRawStringQuote,
             .softKeyword:
            return true
        case let .keyword(keyword):
            return Self.isDeclarationModifierKeyword(keyword)
        default:
            return false
        }
    }

    func parseTail(
        inBlock: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator,
        allowsDeclarationAssignment: Bool = false,
        allowsClassHeaderColon: Bool = false,
        allowsClassDelegation: Bool = false,
        allowsWhereClauseContinuation: Bool = false,
        allowsFunctionWhereClause: Bool = false,
        allowsPropertyDelegation: Bool = false,
        stopsAtFunctionDelegation: Bool = false,
        isClassBody: Bool = false
    ) {
        var progress = false
        var sawAssignment = false
        var sawSupertypeColon = false
        var sawTryKeyword = false
        var sawIfKeyword = false
        var functionTypeNameAfterAnnotation = false
        var delegateBraceTracker = DelegateExpressionBraceTracker()
        var depth = BracketDepth()
        var templateExpressionDepth = 0
        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = depth.isTopLevel
                && templateExpressionDepth == 0
            // A same-line `field:` clause belongs to the property, not its declared type.
            if allowsPropertyDelegation, atTopLevel, depth.angle == 0, !sawAssignment,
               isExplicitBackingFieldStart(token),
               lastConsumedToken?.kind != .symbol(.dot),
               lastConsumedToken?.kind != .symbol(.questionDot)
            {
                break
            }
            if stopsAtFunctionDelegation, atTopLevel, !sawAssignment {
                let expectsTypeName = functionTypeNameAfterAnnotation || canStartTypeName(after: lastConsumedToken?.kind)
                if token.kind == .symbol(.at), expectsTypeName {
                    var work = 0
                    if case let .complete(end) = annotationPrefixEnd(from: 0, work: &work) {
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
               !canStartTypeName(after: lastConsumedToken?.kind)
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
                    ParserBoundaryPolicy.continuesExpressionAfterNewline($0.kind)
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
            if atTopLevel, shouldStopStatementBefore(token, inBlock: inBlock), !isObjectExpressionStart(token),
               isGenuineDeclarationBoundary(token)
            {
                break
            }
            // An annotation preceding an operand is part of the expression,
            // including newlines after '=' or between prefixes and operands.
            // Genuine annotated declarations remain recovery boundaries.
            if atTopLevel, token.kind == .symbol(.at), !startsGenuineDeclaration(at: 0) {
                var work = 0
                if case let .complete(end) = annotationPrefixEnd(from: 0, work: &work) {
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
                let blockID = consumedTokensEndWithWhenSubject(children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock()
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                continue
            }
            if case .symbol(.lBrace) = token.kind, atTopLevel {
                let blockID = consumedTokensEndWithWhenSubject(children)
                    ? parseWhenBody(inBlock: inBlock)
                    : parseBlock(isClassBody: isClassBody)
                children.append(.node(blockID))
                range.append(arena.node(blockID).range)
                progress = true
                // Continue when the block is followed by a continuation keyword of
                // a multi-block expression: `try { } catch { } finally { }` and
                // `if (c) { } else { }` / `else if (c) { } else { }` — or by a
                // symbol that cannot end an expression on its own (`+`, `.`,
                // `?.`, ...), meaning this trailing-lambda call is only part of
                // a larger expression (e.g. `f() { ... } + g() { ... }`).
                let nextAfterBlock = stream.peek()
                if sawTryKeyword {
                    if case .keyword(.catch) = nextAfterBlock.kind { continue }
                    if case .keyword(.finally) = nextAfterBlock.kind { continue }
                }
                if sawIfKeyword, case .keyword(.else) = nextAfterBlock.kind { continue }
                if ParserBoundaryPolicy.continuesExpressionAfterNewline(nextAfterBlock.kind) {
                    // `+` and `-` can begin a prefix-unary expression, so a
                    // newline before them ends the `{ }` statement
                    // (`fun f() { }\n+x` is `f() { }` then `+x`, matching how
                    // Kotlin treats a line starting with `+`/`-` as a new
                    // statement). Same-line `f() { } + g()` still continues.
                    // The remaining continuation symbols cannot start a
                    // statement, so they extend the expression across the
                    // newline (`f() { }\n?.member`, `f() { }\n?: fallback`).
                    let canStartNewStatement = nextAfterBlock.kind == .symbol(.plus)
                        || nextAfterBlock.kind == .symbol(.minus)
                    if !canStartNewStatement || !hasLeadingNewline(nextAfterBlock) {
                        continue
                    }
                }
                if nextAfterBlock.kind == .symbol(.lParen),
                   !hasLeadingNewline(nextAfterBlock)
                {
                    continue
                }
                // A trailing-lambda call can be the receiver of an infix or
                // membership operator. Keep the operator and its operand in
                // the same expression-bodied declaration.
                if isTrailingLambdaOperatorContinuation(nextAfterBlock) {
                    continue
                }
                break
            }
            if case .keyword(.try) = token.kind {
                sawTryKeyword = true
            }
            if case .keyword(.if) = token.kind {
                sawIfKeyword = true
            }
            let consumedToken = consumeToken(into: &children, range: &range)
            progress = true
            delegateBraceTracker.note(consumedToken.kind, atTopLevel: atTopLevel)
            depth.track(token.kind)
            switch token.kind {
            case .templateExprStart:
                templateExpressionDepth += 1
            case .templateExprEnd:
                templateExpressionDepth = max(0, templateExpressionDepth - 1)
            default:
                break
            }
            if case .symbol(.semicolon) = token.kind, atTopLevel {
                break
            }
            if !inBlock, hasLeadingNewline(stream.peek()) {
                let stillGrouped = !depth.isTopLevel
                    || templateExpressionDepth > 0
                if stillGrouped {
                    continue
                }
                // A line ending in `=` or in a binary operator continues onto the
                // next line, so that expression bodies like
                // `= \n try { ... } catch { ... }` or `= 1 +\n    2` are captured
                // in the same declaration node.
                if ParserBoundaryPolicy.continuesExpressionAfterNewline(token.kind)
                    || (allowsFunctionWhereClause && !sawAssignment && token.kind == .softKeyword(.where))
                {
                    // But stop if the next line starts a new declaration
                    // (modifier keyword, declaration keyword, context-parameter
                    // prefix, or annotation) — not merely a modifier / `context`
                    // prefix that is actually introducing an expression
                    // (`suspend { ... }`, `context(...) { ... }`).
                    let nextToken = stream.peek()
                    if startsGenuineDeclaration(at: 0), !isObjectExpressionStart(nextToken) {
                        break
                    }
                    continue
                }
                // A line that starts with `.member` / `?.` / `?:` / `&&` / `||`
                // (or `else` / `catch` / `finally`) can only continue the
                // expression body, as can the line after an infix operator
                // name (`a or\n    (b)`) or after an `if (...)` condition whose
                // branch body starts on the next line.
                // In a class header, a supertype colon may also follow the
                // implicit constructor on the next line. A delegation `by` may
                // begin a line while scanning that supertype list or a property
                // declaration that has not already introduced an initializer.
                if ParserBoundaryPolicy.continuesExpressionBeforeNewline(stream.peek().kind)
                    || (allowsDeclarationAssignment && !sawAssignment && stream.peek().kind == .symbol(.assign))
                    || (allowsPropertyDelegation && !sawAssignment && stream.peek().kind == .softKeyword(.by))
                    || (allowsFunctionWhereClause && !sawAssignment
                        && stream.peek().kind == .softKeyword(.where))
                    || (allowsClassHeaderColon && stream.peek().kind == .symbol(.colon))
                    || (allowsClassDelegation && sawSupertypeColon && stream.peek().kind == .softKeyword(.by))
                    || (allowsWhereClauseContinuation && stream.peek().kind == .softKeyword(.where))
                    || endsWithPendingInfixOperator(children)
                    || endsWithControlFlowCondition(children)
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

    private func canStartTypeName(after kind: TokenKind?) -> Bool {
        guard let kind else { return false }
        switch kind {
        case .symbol(.colon), .symbol(.dot), .symbol(.questionDot), .symbol(.lessThan),
             .symbol(.comma), .symbol(.lParen), .symbol(.arrow),
             .keyword(.in), .softKeyword(.out):
            return true
        default:
            return false
        }
    }
}
