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

        _ = consumeToken(into: &children, range: &range) // '@'

        // Optional use-site target: `@get:`, `@field:`, `@file:`, etc.
        let first = stream.peek()
        if isAnnotationUseSiteTarget(first),
           stream.peek(1).kind == .symbol(.colon)
        {
            _ = consumeToken(into: &children, range: &range)
            _ = consumeToken(into: &children, range: &range)
        }

        // Qualified annotation name: `Foo`, `kotlin.Deprecated`, etc.
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
            while stream.peek().kind == .symbol(.dot),
                  isIdentifierLike(stream.peek(1).kind)
            {
                _ = consumeToken(into: &children, range: &range) // '.'
                _ = consumeToken(into: &children, range: &range) // name segment
            }
        }

        // Optional annotation argument list: `(...)`, allowing nested parens.
        if stream.peek().kind == .symbol(.lParen) {
            var depth = 0
            while !stream.atEOF() {
                let token = consumeToken(into: &children, range: &range)
                if token.kind == .symbol(.lParen) {
                    depth += 1
                } else if token.kind == .symbol(.rParen) {
                    depth -= 1
                    if depth <= 0 {
                        break
                    }
                }
            }
        }

        return true
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

    func parseBalancedGroup(opening: Symbol, closing: Symbol) -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        guard consumeIfSymbol(opening, into: &children, range: &range) else {
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }

        var depth = 1
        while !stream.atEOF(), depth > 0 {
            let token = stream.peek()
            if case let .symbol(symbol) = token.kind, symbol == closing, depth == 1 {
                _ = consumeToken(into: &children, range: &range)
                return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
            }
            if depth == 1, hasLeadingNewline(token), isLikelyTopLevelDeclarationStart(token) {
                break
            }

            _ = consumeToken(into: &children, range: &range)
            if case .symbol(opening) = token.kind {
                depth += 1
            } else if case .symbol(closing) = token.kind {
                depth -= 1
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0004",
            "Unterminated '\(opening.rawValue)' group.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
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
        ParserBoundaryPolicy.shouldStopStatementBefore(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token)
        )
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
        switch kind {
        case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
            true
        default:
            false
        }
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
        message: String
    ) {
        let missingRange = zeroWidthRange(at: stream.peek())
        diagnostics.warning(code, message, range: missingRange)
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
    /// one operand together with a directly preceding call name; a group that
    /// is an `if (...)` / `when (...)` condition ends the run, so
    /// `if (c) foo` is a branch body rather than a pending `foo` operator.
    static func endsWithPendingInfixOperator<C: BidirectionalCollection>(_ tokens: C) -> Bool
        where C.Element == Token
    {
        guard let last = tokens.last, case .identifier = last.kind else {
            return false
        }
        var runLength = 0
        var index = tokens.endIndex
        while index > tokens.startIndex {
            let current = tokens.index(before: index)
            let token = tokens[current]
            switch token.kind {
            case .identifier, .backtickedIdentifier,
                 .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
                 .floatLiteral, .doubleLiteral, .charLiteral,
                 .keyword(.this), .keyword(.true), .keyword(.false), .keyword(.null):
                runLength += 1
                index = current
            case .symbol(.rParen), .symbol(.rBracket):
                let open: TokenKind = token.kind == .symbol(.rParen) ? .symbol(.lParen) : .symbol(.lBracket)
                guard let openIndex = matchingOpenIndex(in: tokens, closingAt: current, open: open, close: token.kind) else {
                    return false
                }
                if token.kind == .symbol(.rParen), endsWithControlFlowCondition(tokens[tokens.startIndex ... current]) {
                    return runLength >= 2 && runLength.isMultiple(of: 2)
                }
                runLength += 1
                index = openIndex
                // Deliberately does not also fold a directly preceding identifier
                // into this run (as it would for a call target in `f(x)`): the
                // token immediately before a parenthesized operand here is at
                // least as likely to be a preceding infix name (`a or (b)`) as a
                // call target, and those are indistinguishable by shape alone.
                // Counting the group as its own run element keeps the
                // alternating operand/operator parity correct either way.
            default:
                return runLength >= 2 && runLength.isMultiple(of: 2)
            }
        }
        return runLength >= 2 && runLength.isMultiple(of: 2)
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
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var index = tokens.startIndex
        while index != endIndex {
            let kind = tokens[index].kind
            let isTopLevel = parenDepth == 0 && bracketDepth == 0 && braceDepth == 0
            if isTopLevel, kind == .keyword(.do) {
                return true
            }
            switch kind {
            case .symbol(.lParen): parenDepth += 1
            case .symbol(.rParen): parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket): bracketDepth += 1
            case .symbol(.rBracket): bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
            index = tokens.index(after: index)
        }
        return false
    }

    /// Tokens that can end an operand: an identifier that follows one of these
    /// is an infix operator name rather than the start of a new statement.
    static func isOperandEndToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier,
             .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral,
             .stringQuote, .rawStringQuote,
             .symbol(.rBracket), .symbol(.rParen),
             .keyword(.this), .keyword(.true), .keyword(.false), .keyword(.null):
            true
        default:
            false
        }
    }

    /// The last `limit` tokens of `children` (in source order), stopping at the
    /// most recent nested node so only the flat tail of the statement is seen.
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
        let token = stream.peek(offset)
        if case let .keyword(keyword) = token.kind,
           Self.isDeclarationModifierKeyword(keyword)
        {
            return startsDeclarationAfterModifier(at: offset + 1)
        }
        return isDeclarationStart(token.kind)
    }

    var invalidRange: SourceRange {
        SourceRange(
            start: SourceLocation(file: FileID.invalid, offset: 0),
            end: SourceLocation(file: FileID.invalid, offset: 0)
        )
    }
}

enum ParserBoundaryPolicy {
    /// Keywords that start declarations or act as statement/synchronization boundaries.
    private static let declarationBoundaryKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import,
    ]

    /// Keywords used as error-recovery synchronization points.
    /// Excludes `.enum` because `enum` is a soft modifier (always followed by `class`)
    /// and was not a synchronization point in the original implementation.
    private static let synchronizationKeywords: Set<Keyword> = [
        .class, .object, .interface, .fun, .val, .var, .typealias, .package, .import,
    ]

    private static let nonSplittingNewlineSymbols: Set<Symbol> = [
        .dot, .comma, .questionDot, .questionQuestion,
        .plus, .minus, .star, .slash,
        .equalEqual, .assign, .arrow,
        .rParen, .rBracket, .rBrace,
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
        case let .keyword(kw) where declarationBoundaryKeywords.contains(kw) || KotlinParser.isDeclarationModifierKeyword(kw):
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

    /// Whether a newline following the just-consumed token continues the current
    /// expression instead of ending the declaration.
    static func continuesExpressionAfterNewline(_ kind: TokenKind) -> Bool {
        if case let .symbol(symbol) = kind {
            return danglingContinuationSymbols.contains(symbol)
        }
        return false
    }

    /// Tokens that can only continue an expression when they begin a line:
    /// `.member`, `?.member`, `?: fallback`, `&&`, `||`, and the `else` /
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
        default:
            return false
        }
    }

    static func shouldSplitStatementOnNewline(_ kind: TokenKind) -> Bool {
        if case let .symbol(symbol) = kind {
            return !nonSplittingNewlineSymbols.contains(symbol)
        }
        return true
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
