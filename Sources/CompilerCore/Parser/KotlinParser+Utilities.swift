extension KotlinParser {
    func parseLeadingDeclarationPrefix(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var consumedAny = true
        while consumedAny {
            consumedAny = false
            if consumeDeclarationAnnotationPrefixIfPresent(into: &children, range: &range) {
                consumedAny = true
                continue
            }
            if case let .keyword(keyword) = stream.peek().kind,
               Self.isDeclarationModifierKeyword(keyword)
            {
                _ = consumeToken(into: &children, range: &range)
                consumedAny = true
            }
        }
    }

    func consumeDeclarationAnnotationPrefixIfPresent(
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) -> Bool {
        guard stream.peek().kind == .symbol(.at) else {
            return false
        }

        _ = consumeToken(into: &children, range: &range)

        let first = stream.peek()
        if isAnnotationUseSiteTarget(first),
           stream.peek(1).kind == .symbol(.colon)
        {
            _ = consumeToken(into: &children, range: &range)
            _ = consumeToken(into: &children, range: &range)
        }

        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
            while stream.peek().kind == .symbol(.dot),
                  isIdentifierLike(stream.peek(1).kind)
            {
                _ = consumeToken(into: &children, range: &range)
                _ = consumeToken(into: &children, range: &range)
            }
        }

        if stream.peek().kind == .symbol(.lParen) {
            _ = consumeToken(into: &children, range: &range)
            var closingSymbols: [Symbol] = [.rParen]
            while !stream.atEOF(), !closingSymbols.isEmpty {
                if closingSymbols.count == 1, hasLeadingNewline(stream.peek()),
                   isAnnotationArgumentRecoveryBoundary(at: 0) {
                    let missingRange = zeroWidthRange(at: stream.peek())
                    diagnostics.error(
                        "KSWIFTK-PARSE-0001", "Expected ')' to close annotation arguments.",
                        range: missingRange
                    )
                    let missing = Token(kind: .missing(expected: .symbol(.rParen)), range: missingRange)
                    children.append(.token(arena.appendToken(missing)))
                    range.append(missingRange)
                    break
                }
                let token = consumeToken(into: &children, range: &range)
                if case let .symbol(symbol) = token.kind {
                    switch symbol {
                    case .lParen: closingSymbols.append(.rParen)
                    case .lBracket: closingSymbols.append(.rBracket)
                    case .lBrace: closingSymbols.append(.rBrace)
                    default:
                        if symbol == closingSymbols.last { closingSymbols.removeLast() }
                    }
                }
            }
        }

        return true
    }

    /// Only named declaration keywords synchronize an unclosed annotation.
    /// Soft keywords such as value/context and nested annotation expressions
    /// remain valid arguments; anonymous functions and objects remain operands.
    func isAnnotationArgumentRecoveryBoundary(at offset: Int) -> Bool {
        let token = stream.peek(offset)
        switch token.kind {
        case .keyword(.fun):
            return stream.peek(offset + 1).kind != .symbol(.lParen)
        case .keyword(.object):
            return stream.peek(offset + 1).kind != .symbol(.colon)
                && stream.peek(offset + 1).kind != .symbol(.lBrace)
        case .keyword(.class):
            let previousKind = offset > 0 ? stream.peek(offset - 1).kind : lastConsumedToken?.kind
            return previousKind != .symbol(.doubleColon) && isIdentifierLike(stream.peek(offset + 1).kind)
        case .keyword(.interface), .keyword(.val), .keyword(.var), .keyword(.typealias):
            return true
        default:
            return false
        }
    }

    func isAnnotationUseSiteTarget(_ token: Token) -> Bool {
        switch token.kind {
        case let .softKeyword(soft):
            return SoftKeyword.useSiteTargets.contains(soft)
        case let .identifier(id), let .backtickedIdentifier(id):
            return SoftKeyword.useSiteTargetNames.contains(interner.resolve(id))
        case let .keyword(keyword):
            return SoftKeyword.useSiteTargetNames.contains(keyword.rawValue)
        default:
            return false
        }
    }

    /// Offset just past the annotation prefix starting at the `@` seen at
    /// `offset`: an optional use-site target (`@field:`), the qualified
    /// annotation name, and an optional balanced argument group. Mirrors the
    /// token shape consumed by `consumeDeclarationAnnotationPrefixIfPresent`
    /// without mutating the parser stream. Returns nil when the qualified
    /// name is missing.
    func offsetPastAnnotationPrefix(from offset: Int) -> Int? {
        var cursor = offset + 1
        if isAnnotationUseSiteTarget(stream.peek(cursor)),
           stream.peek(cursor + 1).kind == .symbol(.colon) {
            cursor += 2
        }
        guard isIdentifierLike(stream.peek(cursor).kind) else { return nil }
        cursor += 1
        while stream.peek(cursor).kind == .symbol(.dot),
              isIdentifierLike(stream.peek(cursor + 1).kind) {
            cursor += 2
        }
        if stream.peek(cursor).kind == .symbol(.lParen) {
            cursor = offsetPastBalancedGroup(from: cursor,
                                             open: .symbol(.lParen), close: .symbol(.rParen))
        }
        return cursor
    }

    func parseBalancedGroup(
        opening: Symbol,
        closing: Symbol,
        allowsValueParameters: Bool = false,
        allowsWhenSubjectVariable: Bool = false
    ) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        guard consumeIfSymbol(opening, into: &children, range: &range) else {
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }

        let parsesValueParameters = allowsValueParameters
            && opening == .lParen && closing == .rParen
        var atValueParameterStart = true
        var valueParameterPrefixEnd: Int?
        var valueParameterTypeArgumentDepth = 0
        var valueParameterInDefaultValue = false
        let whenSubjectVariablePrefixEnd = allowsWhenSubjectVariable
            ? lookaheadWhenSubjectVariablePrefixEnd()
            : nil
        var closingSymbols = [closing]
        while !stream.atEOF() {
            let token = stream.peek()
            if case let .symbol(symbol) = token.kind, symbol == closing, closingSymbols.count == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
            }
            // A proven parameter prefix or anonymous default expression may
            // cross a declaration-looking newline. Keep recovery boundaries
            // for a missing ')' and following named declarations.
            if parsesValueParameters, closingSymbols.count == 1, atValueParameterStart,
               hasLeadingNewline(token), isLikelyTopLevelDeclarationStart(token) {
                valueParameterPrefixEnd = lookaheadValueParameterPrefixEnd()
            }
            let isValueParameterPrefix = parsesValueParameters
                && valueParameterPrefixEnd.map { stream.index < $0 } == true
            let isValueParameterDefaultExpressionStart = parsesValueParameters
                && valueParameterInDefaultValue && startsAnonymousValueParameterDefault()
            let isWhenSubjectVariablePrefix = whenSubjectVariablePrefixEnd.map { stream.index < $0 } == true
            if closingSymbols.count == 1, hasLeadingNewline(token), isLikelyTopLevelDeclarationStart(token),
               !isValueParameterPrefix, !isValueParameterDefaultExpressionStart,
               !isWhenSubjectVariablePrefix {
                break
            }

            if parsesValueParameters, closingSymbols.count == 1 {
                // A generic type's comma is not a new parameter. Conversely,
                // '<' in a default expression may be a comparison, not a type.
                if token.kind == .symbol(.comma), valueParameterTypeArgumentDepth == 0 {
                    atValueParameterStart = true
                    valueParameterPrefixEnd = nil
                    valueParameterInDefaultValue = false
                } else {
                    atValueParameterStart = false
                    if token.kind == .symbol(.assign) {
                        valueParameterInDefaultValue = true
                    } else if token.kind == .symbol(.lessThan) {
                        if !valueParameterInDefaultValue || valueParameterTypeArgumentDepth > 0
                            || valueParameterDefaultStartsTypeArguments() {
                            valueParameterTypeArgumentDepth += 1
                        }
                    } else if token.kind == .symbol(.greaterThan), valueParameterTypeArgumentDepth > 0 {
                        valueParameterTypeArgumentDepth -= 1
                    }
                }
            }
            _ = consumeToken(into: &children, range: &range)
            switch token.kind {
            case .symbol(.lParen):
                closingSymbols.append(.rParen)
            case .symbol(.lBracket):
                closingSymbols.append(.rBracket)
            case .symbol(.lBrace):
                closingSymbols.append(.rBrace)
            case let .symbol(symbol) where symbol == closingSymbols.last:
                closingSymbols.removeLast()
            default:
                break
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0004",
            "Unterminated '\(opening.rawValue)' group.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
    }

    /// Recognizes only the declaration prefix of a `when` subject so a valid
    /// multiline `val` does not look like an unrelated declaration boundary.
    /// Stop at the assignment; the initializer is scanned by the group parser.
    private func lookaheadWhenSubjectVariablePrefixEnd() -> Int? {
        guard stream.peek().kind == .keyword(.val),
              isWhenSubjectVariableName(stream.peek(1)) else {
            return nil
        }

        var offset = 2
        guard stream.peek(offset).kind == .symbol(.colon) else {
            return stream.peek(offset).kind == .symbol(.assign) ? stream.index + offset : nil
        }

        offset += 1
        var depth = BracketDepth()
        var work = 0
        while true {
            guard consumeDeclarationLookaheadWork(&work, at: offset) else { return nil }
            let token = stream.peek(offset)
            guard token.kind != .eof else { return nil }
            let atTypeTopLevel = depth.isTopLevel && depth.angle == 0
            if atTypeTopLevel {
                if token.kind == .symbol(.assign) { return stream.index + offset }
                if token.kind == .symbol(.rParen) || token.kind == .symbol(.lBrace)
                    || token.kind == .symbol(.comma) {
                    return nil
                }
                if hasLeadingNewline(token), isLikelyTopLevelDeclarationStart(token) {
                    return nil
                }
            }
            depth.track(token.kind)
            offset += 1
        }
    }

    private func isWhenSubjectVariableName(_ token: Token) -> Bool {
        switch token.kind {
        case .identifier, .backtickedIdentifier, .softKeyword:
            return true
        case let .keyword(keyword):
            return Self.isDeclarationModifierKeyword(keyword)
        default:
            return false
        }
    }

    private func startsAnonymousValueParameterDefault() -> Bool {
        // Limit shielding to the first token after '='. A completed default
        // must not hide a following declaration when ')' is missing.
        guard lastConsumedToken?.kind == .symbol(.assign) else { return false }
        if stream.peek().kind == .keyword(.fun) {
            return stream.peek(1).kind == .symbol(.lParen)
        }
        return isObjectExpressionStart(stream.peek())
    }

    /// Called once per value-parameter boundary; the cached end also
    /// covers annotations/modifiers split across newlines.
    private func lookaheadValueParameterPrefixEnd() -> Int? {
        var offset = 0
        var work = 0
        while true {
            guard consumeDeclarationLookaheadWork(&work, at: offset) else { return nil }
            let kind = stream.peek(offset).kind
            if kind == .symbol(.at) {
                offset += 1
                if isAnnotationUseSiteTarget(stream.peek(offset)),
                   stream.peek(offset + 1).kind == .symbol(.colon) {
                    offset += 2
                }
                guard isIdentifierLike(stream.peek(offset).kind) else { return nil }
                offset += 1
                while stream.peek(offset).kind == .symbol(.dot),
                      isIdentifierLike(stream.peek(offset + 1).kind) {
                    guard consumeDeclarationLookaheadWork(&work, at: offset) else { return nil }
                    offset += 2
                }
                if stream.peek(offset).kind == .symbol(.lParen) {
                    offset = offsetPastBalancedGroup(from: offset,
                                                    open: .symbol(.lParen), close: .symbol(.rParen))
                    guard stream.peek(offset - 1).kind == .symbol(.rParen) else { return nil }
                }
                continue
            }
            // Modifier keywords can themselves be parameter names (`value:`).
            if isValueParameterName(kind), stream.peek(offset + 1).kind == .symbol(.colon) {
                return stream.index + offset + 2
            }
            if case let .keyword(keyword) = kind, isValueParameterModifier(keyword) {
                offset += 1
                continue
            }
            if kind == .keyword(.val) || kind == .keyword(.var) {
                offset += 1
            }
            guard isValueParameterName(stream.peek(offset).kind),
                  stream.peek(offset + 1).kind == .symbol(.colon) else { return nil }
            return stream.index + offset + 2
        }
    }

    private func isValueParameterModifier(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .public, .private, .internal, .protected, .override, .final, .open, .actual, .expect,
             .vararg, .noinline, .crossinline:
            true
        default:
            false
        }
    }

    private func isValueParameterName(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier, .softKeyword:
            true
        case let .keyword(keyword):
            Self.isDeclarationModifierKeyword(keyword) || keyword == .vararg
        default:
            false
        }
    }

    private func valueParameterDefaultStartsTypeArguments() -> Bool {
        guard let anchor = lastConsumedToken, isIdentifierLike(anchor.kind) else { return false }
        var depth = 0
        // Bound this new lookup before calling the existing generic scanner.
        // Exhaustion only declines shielding; it emits no new diagnostic and
        // never changes the generic scanner's own recovery behavior.
        for offset in 0..<4096 {
            let kind = stream.peek(offset).kind
            if kind == .eof { return false }
            if kind == .symbol(.lessThan) {
                depth += 1
            } else if kind == .symbol(.greaterThan) {
                depth -= 1
                if depth == 0 {
                    let following = stream.peek(offset + 1).kind
                    guard following == .symbol(.lParen) || following == .symbol(.lBrace) else { return false }
                    // A closed generic call shields its commas in a default;
                    // an ordinary comparison leaves parameter commas visible.
                    return canStartTypeArgumentsInternal(hasAnchorToken: true)
                }
            }
        }
        return false
    }

    func parseQualifiedPath(into children: inout [SyntaxChild], range: inout RangeAccumulator, allowImportWildcard: Bool, stopAtAs: Bool = false) {
        var consumed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if shouldStopStatementBefore(token, inBlock: false) {
                break
            }
            // Package/import paths must not consume declaration starts on the next line.
            if consumed, hasLeadingNewline(token) {
                break
            }
            if stopAtAs, case .keyword(.as) = token.kind {
                break
            }
            if case .symbol(.dot) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if isIdentifierLike(token.kind) {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            if allowImportWildcard, case .symbol(.star) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                consumed = true
                continue
            }
            break
        }
        if !consumed {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0003", message: "Expected name in package/import path.")
        }
    }

    func consumeIf(expected: TokenKind, into children: inout [SyntaxChild], range: inout RangeAccumulator, code: String) {
        if stream.peek().kind == expected {
            _ = consumeToken(into: &children, range: &range)
            return
        }
        insertMissingToken(expected: expected, into: &children, range: &range, code: code, message: "Expected \(expected).")
    }

    func consumeIfSymbol(_ symbol: Symbol, into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Bool {
        if case .symbol(symbol) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            return true
        }
        return false
    }

    func consumeToken(into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Token {
        let token = stream.advance()
        let tokenID = arena.appendToken(token)
        let child: SyntaxChild = .token(tokenID)
        children.append(child)
        range.append(token.range)
        if token.kind != .eof {
            lastConsumedToken = token
        }
        return token
    }

    func childRange(_ child: SyntaxChild) -> SourceRange {
        switch child {
        case let .token(tokenID):
            guard let token = arena.token(tokenID) else { return invalidRange }
            return token.range
        case let .node(nodeID):
            return arena.node(nodeID).range
        }
    }

    func shouldStopStatementBefore(_ token: Token, inBlock: Bool) -> Bool {
        if isLabelStart { return false }
        return ParserBoundaryPolicy.shouldStopStatementBefore(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
    }

    var isLabelStart: Bool {
        stream.peek().kind.isLabelName && stream.peek(1).kind == .symbol(.at)
    }

    static func isDeclarationModifierKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final, .crossinline, .noinline, .tailrec,
             .inline, .suspend, .operator, .infix, .external, .value:
            true
        default:
            false
        }
    }

    func isDeclarationKeyword(_ keyword: Keyword) -> Bool {
        if Self.isDeclarationModifierKeyword(keyword) {
            return true
        }
        switch keyword {
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import, .companion:
            return true
        default:
            return false
        }
    }

    func isDeclarationStart(_ kind: TokenKind) -> Bool {
        if kind == .symbol(.at) {
            return true
        }
        if case let .keyword(keyword) = kind, isDeclarationKeyword(keyword) {
            return true
        }
        if case .softKeyword(.context) = kind {
            return true
        }
        return false
    }

    func isIdentifierLike(_ kind: TokenKind) -> Bool {
        kind.isLabelName
    }

    func isLoopStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.for), .keyword(.while), .keyword(.do):
            true
        default:
            false
        }
    }

    func hasLeadingNewline(_ token: Token) -> Bool {
        token.leadingTrivia.contains(.newline)
    }

    func appendOptionalTerminator(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        if !stream.atEOF(), case .symbol(.semicolon) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
    }

    func zeroWidthRange(at token: Token) -> SourceRange {
        let loc = token.range.start
        return SourceRange(start: loc, end: loc)
    }

    func insertMissingToken(
        expected: TokenKind,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator,
        code: String,
        message: String,
        severity: DiagnosticSeverity = .warning
    ) {
        let missingRange = zeroWidthRange(at: stream.peek())
        switch severity {
        case .error:
            diagnostics.error(code, message, range: missingRange)
        case .warning:
            diagnostics.warning(code, message, range: missingRange)
        case .note:
            diagnostics.note(code, message, range: missingRange)
        case .info:
            diagnostics.info(code, message, range: missingRange)
        }
        let missingToken = Token(kind: .missing(expected: expected), range: missingRange)
        let tokenID = arena.appendToken(missingToken)
        children.append(.token(tokenID))
        range.append(missingRange)
    }

    func isSynchronizationPoint(_ token: Token, inBlock: Bool) -> Bool {
        ParserBoundaryPolicy.isSynchronizationPoint(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
    }

    func skipToSynchronizationPoint(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        let skippedStart = stream.peek().range
        if !inBlock, case .symbol(.rBrace) = stream.peek().kind {
            // Consume an unmatched file-scope brace without skipping the valid
            // top-level declarations or statements that follow it.
            _ = consumeToken(into: &children, range: &range)
            diagnostics.error(
                "KSWIFTK-PARSE-0006",
                "Skipped 1 unexpected token(s).",
                range: skippedStart
            )
            return
        }

        var skippedCount = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if isSynchronizationPoint(token, inBlock: inBlock) {
                break
            }
            _ = consumeToken(into: &children, range: &range)
            skippedCount += 1
        }
        if skippedCount > 0 {
            diagnostics.error(
                "KSWIFTK-PARSE-0006",
                "Skipped \(skippedCount) unexpected token(s).",
                range: skippedStart
            )
        }
    }

    func isLikelyTopLevelDeclarationStart(_ token: Token) -> Bool {
        if token.kind == .symbol(.at) {
            return true
        }
        if case let .keyword(keyword) = token.kind {
            if Self.isDeclarationModifierKeyword(keyword) {
                return startsDeclarationAfterModifier(at: 0)
            }
            return isDeclarationStart(token.kind)
        }
        // `context` only introduces a declaration as a context-parameter
        // prefix (`context(x: T) fun f()`). A parameter or property named
        // `context` at the start of a line inside a multiline group
        // (`fun f(\n    context: T,\n ...)`) must not terminate that group.
        if case .softKeyword(.context) = token.kind {
            return stream.peek(1).kind == .symbol(.lParen)
        }
        return isDeclarationStart(token.kind)
    }

    /// Whether the tokens consumed so far end in an infix function name, so a
    /// newline after it continues the expression (`a or\n    (b)`). Kotlin's
    /// grammar allows `{NL}` after an infix identifier, and an identifier that
    /// directly follows an operand can only be an infix call name.
    func endsWithPendingInfixOperator(_ children: [SyntaxChild]) -> Bool {
        let trailing = trailingTokens(of: children, limit: 64)
        return Self.endsWithPendingInfixOperator(trailing[...])
    }

    /// An infix chain alternates operands and operator names
    /// (`a or b shl c`), so the tail of a statement is a *pending* infix
    /// operator exactly when the trailing run of operand / identifier tokens
    /// has even length and ends in an identifier: `x = a or` (2) is pending,
    /// `x = a or b` (3) is complete. Parenthesized / indexed groups count as
    /// one operand together with their call target and qualified receiver; a group that
    /// is an `if (...)` / `when (...)` condition ends the run, so
    /// `if (c) foo` is a branch body rather than a pending `foo` operator.
    static func endsWithPendingInfixOperator<C: BidirectionalCollection>(_ tokens: C) -> Bool
        where C.Element == Token
    {
        guard let last = tokens.last, case .identifier = last.kind else {
            return false
        }
        // If the trailing identifier is preceded by `.`, `?.`, or `::`, it is a
        // qualified member access / property / method, not an infix operator name.
        let lastIndex = tokens.index(before: tokens.endIndex)
        if lastIndex > tokens.startIndex {
            let beforeLast = tokens[tokens.index(before: lastIndex)].kind
            if beforeLast == .symbol(.dot) || beforeLast == .symbol(.questionDot) || beforeLast == .symbol(.doubleColon) {
                return false
            }
        }
        var runLength = 0
        var index = tokens.endIndex
        while index > tokens.startIndex {
            let current = tokens.index(before: index)
            let token = tokens[current]
            if token.kind.isLabelName, current > tokens.startIndex {
                let at = tokens.index(before: current)
                if tokens[at].kind == .symbol(.at) {
                    // A return label is not an operand or an infix operator.
                    // Keep a qualified `this@label` together as one operand.
                    if at > tokens.startIndex {
                        let receiver = tokens.index(before: at)
                        if tokens[receiver].kind == .keyword(.this) || tokens[receiver].kind == .keyword(.super) {
                            runLength += 1
                            index = receiver
                            continue
                        }
                    }
                    return runLength >= 2 && runLength.isMultiple(of: 2)
                }
            }
            switch token.kind {
            case .identifier, .backtickedIdentifier,
                 .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral,
                 .keyword(.this), .keyword(.true), .keyword(.false), .keyword(.null):
                runLength += 1
                index = postfixOperandStart(in: tokens, endingAt: current)
            case .symbol(.rParen), .symbol(.rBracket):
                let open: TokenKind = token.kind == .symbol(.rParen) ? .symbol(.lParen) : .symbol(.lBracket)
                guard matchingOpenIndex(in: tokens, closingAt: current, open: open, close: token.kind) != nil else {
                    return false
                }
                if token.kind == .symbol(.rParen), endsWithControlFlowCondition(tokens[tokens.startIndex ... current]) {
                    return runLength >= 2 && runLength.isMultiple(of: 2)
                }
                runLength += 1
                index = postfixOperandStart(in: tokens, endingAt: current)
            default:
                return runLength >= 2 && runLength.isMultiple(of: 2)
            }
        }
        return runLength >= 2 && runLength.isMultiple(of: 2)
    }

    private static func postfixOperandStart<C: BidirectionalCollection>(
        in tokens: C, endingAt end: C.Index
    ) -> C.Index where C.Element == Token {
        var start = end
        var current = end

        if tokens[current].kind == .symbol(.rParen) || tokens[current].kind == .symbol(.rBracket) {
            let open: TokenKind = tokens[current].kind == .symbol(.rParen) ? .symbol(.lParen) : .symbol(.lBracket)
            guard let openIndex = matchingOpenIndex(in: tokens, closingAt: current, open: open, close: tokens[current].kind) else {
                return end
            }
            start = openIndex
            current = openIndex

            if tokens[end].kind == .symbol(.rBracket), current > tokens.startIndex {
                let target = tokens.index(before: current)
                start = postfixOperandStart(in: tokens, endingAt: target)
                current = start
            } else if tokens[end].kind == .symbol(.rParen), current > tokens.startIndex {
                let target = tokens.index(before: current)
                let isPrecededByDot: Bool = {
                    guard target > tokens.startIndex else { return false }
                    let beforeTarget = tokens[tokens.index(before: target)].kind
                    return beforeTarget == .symbol(.dot) || beforeTarget == .symbol(.questionDot)
                }()
                let isFollowedByDot: Bool = {
                    let afterEnd = tokens.index(after: end)
                    guard afterEnd < tokens.endIndex else { return false }
                    let kind = tokens[afterEnd].kind
                    return kind == .symbol(.dot) || kind == .symbol(.questionDot)
                }()
                if isPrecededByDot || isFollowedByDot {
                    switch tokens[target].kind {
                    case .identifier, .backtickedIdentifier:
                        start = postfixOperandStart(in: tokens, endingAt: target)
                        current = start
                    default:
                        break
                    }
                }
            }
        }

        while current > tokens.startIndex {
            let prev = tokens.index(before: current)
            switch tokens[prev].kind {
            case .symbol(.bangBang):
                current = prev
                start = prev
            case .symbol(.dot), .symbol(.questionDot):
                guard prev > tokens.startIndex else { break }
                let receiverEnd = tokens.index(before: prev)
                let receiverStart = postfixOperandStart(in: tokens, endingAt: receiverEnd)
                current = receiverStart
                start = receiverStart
            default:
                return start
            }
        }

        return start
    }

    private static func matchingOpenIndex<C: BidirectionalCollection>(
        in tokens: C, closingAt closeIndex: C.Index, open: TokenKind, close: TokenKind
    ) -> C.Index? where C.Element == Token {
        var depth = 0
        var index = closeIndex
        while true {
            let kind = tokens[index].kind
            if kind == close {
                depth += 1
            } else if kind == open {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            guard index > tokens.startIndex else { return nil }
            index = tokens.index(before: index)
        }
    }

    /// Whether the tokens consumed so far end with the closing `)` of an
    /// `if (...)` / `when (...)` condition, whose body may start on the next
    /// line (`if (a)\n    if (b) 1\n    else 2\nelse 3`).
    func endsWithControlFlowCondition(_ children: [SyntaxChild]) -> Bool {
        let trailing = trailingTokens(of: children, limit: 64)
        guard Self.endsWithControlFlowCondition(trailing[...]) else {
            return false
        }
        // A labeled braced do-while is parsed by the generic statement path:
        // `label@ do`, the body block node, then `while (...)`. `trailingTokens`
        // deliberately stops at that block node, so the static token-only check
        // cannot see the earlier `do` and would treat the closing condition as a
        // standalone while whose body continues on the next line.
        if let opener = Self.trailingControlFlowConditionOpener(trailing[...]),
           opener.kind == .keyword(.while),
           containsDirectDoKeyword(children)
        {
            return false
        }
        return true
    }

    private func containsDirectDoKeyword(_ children: [SyntaxChild]) -> Bool {
        children.contains { child in
            guard case let .token(tokenID) = child,
                  let token = arena.token(tokenID)
            else {
                return false
            }
            return token.kind == .keyword(.do)
        }
    }

    static func endsWithControlFlowCondition<C: BidirectionalCollection>(_ tokens: C) -> Bool
        where C.Element == Token
    {
        guard let opener = trailingControlFlowConditionOpener(tokens) else {
            return false
        }
        switch opener.kind {
        case .keyword(.if), .keyword(.when), .keyword(.for), .keyword(.catch):
            return true
        case .keyword(.while):
            // A standalone `while (condition)` may continue with its body on
            // the next line. The trailing condition of a completed
            // `do { ... } while (condition)` must not consume the following
            // statement, however.
            return !hasTopLevelDoKeyword(in: tokens, before: opener.index)
        default:
            return false
        }
    }

    private static func trailingControlFlowConditionOpener<C: BidirectionalCollection>(
        _ tokens: C
    ) -> (kind: TokenKind, index: C.Index)? where C.Element == Token {
        guard let last = tokens.last, last.kind == .symbol(.rParen) else {
            return nil
        }
        var depth = 0
        var index = tokens.index(before: tokens.endIndex)
        while true {
            let token = tokens[index]
            if token.kind == .symbol(.rParen) {
                depth += 1
            } else if token.kind == .symbol(.lParen) {
                depth -= 1
                if depth == 0 {
                    guard index > tokens.startIndex else { return nil }
                    let openerIndex = tokens.index(before: index)
                    return (tokens[openerIndex].kind, openerIndex)
                }
            }
            guard index > tokens.startIndex else { return nil }
            index = tokens.index(before: index)
        }
    }

    private static func hasTopLevelDoKeyword<C: BidirectionalCollection>(
        in tokens: C,
        before endIndex: C.Index
    ) -> Bool where C.Element == Token {
        var depth = BracketDepth()
        var index = tokens.startIndex
        while index != endIndex {
            let kind = tokens[index].kind
            if depth.isTopLevel, kind == .keyword(.do) {
                return true
            }
            depth.track(kind)
            index = tokens.index(after: index)
        }
        return false
    }


    /// Stops at the most recent nested node so only the flat tail of the
    /// statement is seen.
    private func trailingTokens(of children: [SyntaxChild], limit: Int) -> [Token] {
        var collected: [Token] = []
        for child in children.reversed() {
            guard case let .token(tokenID) = child, let token = arena.token(tokenID) else {
                break
            }
            collected.append(token)
            if collected.count == limit {
                break
            }
        }
        return collected.reversed()
    }

    /// A modifier keyword at the start of a new line is only a declaration
    /// boundary when a real declaration keyword follows it. This keeps a
    /// modifier keyword used as a parameter name inside a multiline group
    /// from prematurely terminating that group.
    private func startsDeclarationAfterModifier(at offset: Int) -> Bool {
        var cursor = offset
        var work = 0
        var prefixIndices: [Int] = []
        while true {
            let absoluteIndex = stream.index + cursor
            if let cached = modifierDeclarationLookahead[absoluteIndex] {
                for index in prefixIndices {
                    modifierDeclarationLookahead[index] = cached
                }
                return cached
            }
            guard consumeDeclarationLookaheadWork(&work, at: cursor) else {
                for index in prefixIndices {
                    modifierDeclarationLookahead[index] = true
                }
                modifierDeclarationLookahead[stream.index + offset] = true
                return true
            }
            let token = stream.peek(cursor)
            guard case let .keyword(keyword) = token.kind,
                  Self.isDeclarationModifierKeyword(keyword)
            else {
                let result = isDeclarationStart(token.kind)
                for index in prefixIndices {
                    modifierDeclarationLookahead[index] = result
                }
                modifierDeclarationLookahead[absoluteIndex] = result
                return result
            }
            prefixIndices.append(absoluteIndex)
            cursor += 1
        }
    }

    var invalidRange: SourceRange {
        SourceRange(
            start: SourceLocation(file: FileID.invalid, offset: 0),
            end: SourceLocation(file: FileID.invalid, offset: 0)
        )
    }

    /// Bracket nesting tracked while flat-scanning tokens. Unmatched closers
    /// clamp at zero so one-sided groups cannot drive a count negative. Each
    /// loop reads only the counters it needs: `isTopLevel` deliberately
    /// excludes `angle`, because an unmatched `<`/`>` may be a comparison
    /// operator rather than a type-argument list.
    struct BracketDepth {
        var angle = 0
        var paren = 0
        var bracket = 0
        var brace = 0

        var isTopLevel: Bool {
            paren == 0 && bracket == 0 && brace == 0
        }

        mutating func track(_ kind: TokenKind) {
            switch kind {
            case .symbol(.lessThan): angle += 1
            case .symbol(.greaterThan): angle = max(0, angle - 1)
            case .symbol(.lParen): paren += 1
            case .symbol(.rParen): paren = max(0, paren - 1)
            case .symbol(.lBracket): bracket += 1
            case .symbol(.rBracket): bracket = max(0, bracket - 1)
            case .symbol(.lBrace): brace += 1
            case .symbol(.rBrace): brace = max(0, brace - 1)
            default: break
            }
        }
    }
}

enum ParserBoundaryPolicy {
    /// Keywords that start declarations or terminate a preceding expression on a new line.
    private static let newlineBoundaryKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import, .return,
    ]

    /// Excludes `.enum` because `enum` is a soft modifier (always followed by `class`)
    /// and was not a synchronization point in the original implementation.
    private static let synchronizationKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .package, .import,
    ]

    private static let nonSplittingNewlineSymbols: Set<Symbol> = [
        .dot, .comma, .questionDot, .questionColon, .ampAmp, .barBar,
        .rParen, .rBracket,
    ]

    /// Symbols that cannot end an expression, so a newline right after one is a
    /// line continuation rather than a statement/declaration boundary
    /// (`fun f(): Int = 1 +\n    2`). `<`, `>`, `?` and postfix operators are
    /// excluded because they legitimately end a type or an expression.
    private static let danglingContinuationSymbols: Set<Symbol> = [
        .plus, .minus, .star, .slash, .percent,
        .ampAmp, .barBar,
        .equalEqual, .bangEqual, .tripleEqual, .notTripleEqual,
        .lessOrEqual, .greaterOrEqual,
        .assign, .plusAssign, .minusAssign, .starAssign, .slashAssign, .percentAssign,
        .dotDot, .dotDotLt, .questionQuestion, .questionColon,
        .comma, .dot, .questionDot, .colon, .arrow, .doubleColon,
    ]

    static func shouldStopStatementBefore(
        _ token: Token,
        inBlock: Bool,
        hasLeadingNewline: Bool
    ) -> Bool {
        if token.kind == .eof {
            return true
        }
        switch token.kind {
        case .symbol(.rBrace):
            return true
        case .symbol(.at):
            return !inBlock && hasLeadingNewline
        case let .keyword(kw) where newlineBoundaryKeywords.contains(kw) || KotlinParser.isDeclarationModifierKeyword(kw):
            return !inBlock && hasLeadingNewline
        default:
            return false
        }
    }

    static func isSynchronizationPoint(
        _ token: Token,
        inBlock: Bool,
        hasLeadingNewline: Bool
    ) -> Bool {
        switch token.kind {
        case .eof:
            return true
        case .symbol(.rBrace):
            // A closing brace is a synchronization point only inside a block.
            // At file scope it is unexpected input that the top-level recovery
            // node must consume and diagnose before parsing the next declaration.
            return inBlock
        case let .keyword(kw) where synchronizationKeywords.contains(kw):
            return true
        default:
            break
        }
        if inBlock {
            switch token.kind {
            case .symbol(.semicolon):
                return true
            case .keyword(.catch), .keyword(.finally), .keyword(.else):
                return true
            default:
                if hasLeadingNewline {
                    return true
                }
            }
        }
        return false
    }

    static func continuesExpressionAfterNewline(_ kind: TokenKind) -> Bool {
        // Both class and property delegation require an expression after `by`;
        // `else` requires a branch expression, which may start on the next line;
        // a cast may also continue a block-bodied expression after its closing brace.
        if kind == .softKeyword(.by) || kind == .keyword(.as) {
            return true
        }
        if kind == .keyword(.else) {
            return true
        }
        if case let .symbol(symbol) = kind {
            return danglingContinuationSymbols.contains(symbol)
        }
        return false
    }

    /// Tokens that can only continue an expression when they begin a line:
    /// `.member`, `?.member`, `?: fallback`, `&&`, `||`, `as`, and the `else` /
    /// `catch` / `finally` continuation keywords never start a statement, so a
    /// newline before one of them keeps the current declaration going
    /// (`fun f() =\n    xs\n        .map { ... }`).
    private static let leadingContinuationSymbols: Set<Symbol> = [
        .dot, .questionDot, .questionColon, .ampAmp, .barBar,
    ]

    static func continuesExpressionBeforeNewline(_ kind: TokenKind) -> Bool {
        switch kind {
        case let .symbol(symbol):
            return leadingContinuationSymbols.contains(symbol)
        case .keyword(.else), .keyword(.catch), .keyword(.finally):
            return true
        case .keyword(.as):
            return true
        default:
            return false
        }
    }

    static func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        if kind == .keyword(.as) { return false }
        if case let .symbol(symbol) = kind {
            return !nonSplittingNewlineSymbols.contains(symbol)
        }
        return true
    }
}

/// Tracks a `by` delegate expression while flat-scanning a class/object
/// supertype list, so a top-level `{` can be classified as part of the
/// delegate expression — the body of `when`, `if`/`else`, `try`/`catch`/
/// `finally`, or `do`, an object literal's body, or a lambda directly after
/// `by` — versus the declaration's own body. kotlinc never parses a
/// trailing lambda in this position: `C by run { x }` reports "function
/// invocation 'run(...)' expected" and treats the brace as the class body.
struct DelegateExpressionBraceTracker {
    /// A top-level `by` introduced a delegate expression in the current
    /// supertype entry.
    private(set) var sawBy = false
    /// An `object` literal's body brace is still expected; commas before it
    /// separate the literal's own supertypes, not class supertype entries.
    private(set) var objectPendingBody = false
    /// The token consumed just before the current position.
    private var previous: TokenKind?
    /// For each open `(`-group, whether it directly follows a control
    /// keyword whose body is a brace block (`when (x) {`, `if (c) {`,
    /// `catch (e) {`, ...).
    private var parenFollowsControlKeyword: [Bool] = []
    /// Whether the most recently consumed `)` closed such a paren group.
    private var closedParenFollowsControlKeyword = false

    /// Records `kind` as consumed. `atTopLevel` is the caller's bracket
    /// depth state *before* this token, so `by`, `object`, and entry-ending
    /// commas only count outside every open group.
    mutating func note(_ kind: TokenKind, atTopLevel: Bool) {
        if atTopLevel {
            if kind == .softKeyword(.by) {
                sawBy = true
            } else if kind == .symbol(.comma), !objectPendingBody {
                // A top-level comma starts the next supertype entry.
                sawBy = false
            }
            if sawBy, kind == .keyword(.object) {
                objectPendingBody = true
            }
            if objectPendingBody, kind == .symbol(.lBrace) {
                objectPendingBody = false
            }
        }
        if sawBy {
            switch kind {
            case .symbol(.lParen):
                parenFollowsControlKeyword.append(Self.isBraceBodiedControlKeyword(previous))
            case .symbol(.rParen):
                closedParenFollowsControlKeyword = parenFollowsControlKeyword.popLast() ?? false
            default:
                break
            }
        }
        previous = kind
    }

    /// Ends the current supertype entry after a `,` that was consumed as an
    /// entry separator rather than fed through `note`.
    mutating func reset() {
        self = DelegateExpressionBraceTracker()
    }

    /// A top-level `,` ends a supertype entry unless it separates an object
    /// literal's own supertypes (`by object : A, B { ... }`).
    var commaEndsSupertypeEntry: Bool {
        !objectPendingBody
    }

    /// Whether a `{` at the current top-level position belongs to the
    /// delegate expression rather than starting the declaration body.
    func braceContinuesDelegateExpression() -> Bool {
        guard sawBy else { return false }
        if objectPendingBody { return true }
        switch previous {
        case .softKeyword(.by),
             .keyword(.when), .keyword(.if), .keyword(.else),
             .keyword(.try), .keyword(.finally), .keyword(.do),
             .keyword(.object):
            return true
        case .symbol(.rParen):
            return closedParenFollowsControlKeyword
        default:
            return false
        }
    }

    private static func isBraceBodiedControlKeyword(_ kind: TokenKind?) -> Bool {
        switch kind {
        case .keyword(.when), .keyword(.if), .keyword(.catch),
             .keyword(.for), .keyword(.while):
            return true
        default:
            return false
        }
    }
}

extension Token {
    var rangeIfAvailable: SourceRange {
        range
    }
}

struct RangeAccumulator {
    var value: SourceRange?

    mutating func append(_ range: SourceRange) {
        if let current = value {
            value = SourceRange(start: current.start, end: range.end)
        } else {
            value = range
        }
    }
}
