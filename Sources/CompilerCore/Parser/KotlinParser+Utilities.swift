extension KotlinParser {
    func parseLeadingDeclarationPrefix(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        consumeLeadingPrefix(.declaration, into: &children, range: &range)
    }

    func consumeLeadingPrefix(
        _ mode: LeanParser.LeadingPrefixMode,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        guard let result = LeanParser.scanLeadingPrefix(self, mode: mode) else { return }
        appendScannedLeadingPrefix(result.consumed, recovered: result.recovered, into: &children, range: &range)
    }

    func appendScannedLeadingPrefix(
        _ consumed: Int, recovered: Bool, into children: inout [SyntaxChild], range: inout RangeAccumulator
    ) {
        for _ in 0 ..< consumed {
            _ = consumeToken(into: &children, range: &range)
        }
        if recovered {
            let missingRange = zeroWidthRange(at: stream.peek())
            diagnostics.error(
                "KSWIFTK-PARSE-0001", "Expected ')' to close annotation arguments.",
                range: missingRange
            )
            let missing = Token(kind: .missing(expected: .symbol(.rParen)), range: missingRange)
            children.append(.token(arena.appendToken(missing)))
            range.append(missingRange)
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

    func isReceiverUseSiteTarget(_ token: Token) -> Bool {
        switch token.kind {
        case .softKeyword(.receiver):
            return true
        case let .identifier(id), let .backtickedIdentifier(id):
            return interner.resolve(id) == "receiver"
        case let .keyword(keyword):
            return keyword.rawValue == "receiver"
        default:
            return false
        }
    }

    func offsetPastAnnotationPrefix(from offset: Int) -> Int? {
        LeanParser.offsetPastAnnotation(self, from: offset)
    }

    func parseBalancedGroup(
        opening: Symbol,
        closing: Symbol,
        allowsValueParameters: Bool = false,
        allowsWhenSubjectVariable: Bool = false
    ) -> NodeID {
        guard let result = LeanParser.scanBalancedGroup(
            self, opening: opening, closing: closing, allowsValueParameters: allowsValueParameters,
            allowsWhenSubjectVariable: allowsWhenSubjectVariable
        ) else {
            reportUnavailableLeanParser()
            return arena.appendNode(kind: .statement, range: invalidRange, [])
        }
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        for _ in 0 ..< result.consumed {
            _ = consumeToken(into: &children, range: &range)
        }
        if result.unterminated {
            diagnostics.warning(
                "KSWIFTK-PARSE-0004",
                "Unterminated '\(opening.rawValue)' group.",
                range: stream.peek().rangeIfAvailable
            )
        }
        return arena.appendNode(kind: .statement, range: range.value ?? invalidRange, children)
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
        return LeanParser.shouldStopStatementBefore(
            token,
            inBlock: inBlock,
            hasLeadingNewline: hasLeadingNewline(token),
            diagnostics: diagnostics
        )
    }

    var isLabelStart: Bool {
        LeanParser.isLabelStart(self)
    }

    static func isDeclarationModifierKeyword(_ keyword: Keyword) -> Bool {
        switch keyword {
        case .public, .private, .internal, .protected, .open, .abstract, .sealed, .data, .annotation,
             .inner, .expect, .actual, .const, .lateinit, .override, .final, .crossinline, .noinline, .tailrec,
             .inline, .suspend, .operator, .infix, .external, .value, .vararg:
            true
        default:
            false
        }
    }

    static func isDeclarationKeyword(_ keyword: Keyword) -> Bool {
        if Self.isDeclarationModifierKeyword(keyword) {
            return true
        }
        switch keyword {
        // `import` is only a directive at compilation-unit level; inside
        // blocks it is an ordinary identifier (KUU-4363).
        case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .companion:
            return true
        default:
            return false
        }
    }

    func isDeclarationStart(_ kind: TokenKind) -> Bool {
        LeanParser.isBareDeclarationStart(self, kind: kind)
    }

    func isIdentifierLike(_ kind: TokenKind) -> Bool {
        kind.isLabelName
    }

    func hasLeadingNewline(_ token: Token) -> Bool {
        token.leadingTrivia.contains(.newline)
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

    func skipToSynchronizationPoint(
        inBlock: Bool,
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) {
        let skippedCount = LeanParser.recoverySkipCount(self, inBlock: inBlock) ?? 0
        consumeSkippedTokens(skippedCount, into: &children, range: &range)
    }

    func consumeSkippedTokens(_ skippedCount: Int, into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        guard skippedCount > 0 else { return }
        let skippedStart = stream.peek().range
        for _ in 0..<skippedCount {
            _ = consumeToken(into: &children, range: &range)
        }
        diagnostics.error(
            "KSWIFTK-PARSE-0006",
            "Skipped \(skippedCount) unexpected token(s).",
            range: skippedStart
        )
    }

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
        guard let last = tokens.last else {
            return false
        }
        // A trailing symbolic operator or member-access separator can never
        // complete a statement — `a ||`, `x +`, `foo.`, `a is` all require a
        // following operand, so a newline after them continues the expression
        // rather than starting a new one.
        // Bare `<`/`>` are excluded: they also close type-argument lists
        // (`is List<Int>`), which legitimately end a condition or statement.
        switch last.kind {
        case .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash),
             .symbol(.percent), .symbol(.equalEqual), .symbol(.bangEqual),
             .symbol(.tripleEqual), .symbol(.notTripleEqual),
             .symbol(.lessOrEqual), .symbol(.greaterOrEqual),
             .symbol(.ampAmp), .symbol(.barBar), .symbol(.questionColon),
             .symbol(.dotDot), .symbol(.dotDotLt), .symbol(.dot),
             .symbol(.questionDot), .symbol(.doubleColon):
            return true
        case .keyword(.is), .keyword(.in):
            return true
        default:
            break
        }
        guard case .identifier = last.kind else {
            return false
        }
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
            case .symbol(.bangBang):
                // `!!` is a postfix on the operand that precedes it, not a
                // separate alternation element. Skip it so `a!! or b`
                // keeps operand parity.
                index = current
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

        if tokens[current].kind == .symbol(.bangBang), current > tokens.startIndex {
            return postfixOperandStart(in: tokens, endingAt: tokens.index(before: current))
        }

        if tokens[current].kind == .symbol(.rParen) || tokens[current].kind == .symbol(.rBracket) {
            let open: TokenKind = tokens[current].kind == .symbol(.rParen) ? .symbol(.lParen) : .symbol(.lBracket)
            guard let openIndex = matchingOpenIndex(in: tokens, closingAt: current, open: open, close: tokens[current].kind) else {
                return end
            }
            start = openIndex
            current = openIndex

            // A `(`/`[` group is a call-argument or index postfix only when
            // the token in front of the opener completes an operand (`f()`,
            // `a.b()`, `a[i]`). After an infix *name* the group is the next
            // operand instead — `a or (b)` keeps `or` in the name slot and
            // `(b)` as its operand. Checking operand position rather than
            // only `.`-adjacency keeps an unqualified `f()` receiver inside
            // one operand; otherwise `x = f() or y` counts `f` and `()`
            // separately, flips the pending-infix parity, and swallows the
            // next statement.
            if current > tokens.startIndex,
               isOperandEnd(in: tokens, endingAt: tokens.index(before: current))
            {
                let target = tokens.index(before: current)
                start = postfixOperandStart(in: tokens, endingAt: target)
                current = start
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

    private static func isOperandEnd<C: BidirectionalCollection>(
        in tokens: C, endingAt end: C.Index
    ) -> Bool where C.Element == Token {
        switch tokens[end].kind {
        case .identifier, .backtickedIdentifier:
            guard end > tokens.startIndex else { return true }
            return !isOperandEnd(in: tokens, endingAt: tokens.index(before: end))
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral,
             .stringQuote, .rawStringQuote, .multiDollarStringQuote,
             .multiDollarRawStringQuote, .templateExprEnd,
             .keyword(.this), .keyword(.super), .keyword(.true),
             .keyword(.false), .keyword(.null),
             .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace),
             .symbol(.bangBang):
            return true
        default:
            return false
        }
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
        /// Open `${ ... }` string-template groups. A newline inside a template
        /// expression is never a statement boundary, so boundary checks gate
        /// on `template == 0` — but `isTopLevel` deliberately excludes it: a
        /// `{` inside a template must still reach the block/`when`-body
        /// parser like one inside `(`.
        var template = 0

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
            case .templateExprStart: template += 1
            case .templateExprEnd: template = max(0, template - 1)
            default: break
            }
        }
    }
}

/// Tracks a `by` delegate expression while flat-scanning class/object headers
/// and property initializers containing object literals, so a top-level `{`
/// can be classified as part of the delegate expression — the body of `when`,
/// `if`/`else`, `try`/`catch`/`finally`, or `do`, an object literal's body, or a
/// lambda directly after `by` — versus the declaration's own body. kotlinc
/// never parses a trailing lambda in this position: `C by run { x }` reports
/// "function invocation 'run(...)' expected" and treats the brace as the class body.
struct DelegateExpressionBraceTracker {
    private(set) var sawBy = false
    private(set) var objectPendingBody = false
    private var previous: TokenKind?
    private var parenFollowsControlKeyword: [Bool] = []
    private var closedParenFollowsControlKeyword = false

    mutating func note(_ kind: TokenKind, atTopLevel: Bool) {
        if atTopLevel {
            if kind == .softKeyword(.by) {
                sawBy = true
            } else if kind == .symbol(.comma), !objectPendingBody {
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

    mutating func reset() {
        self = DelegateExpressionBraceTracker()
    }

    var commaEndsSupertypeEntry: Bool {
        !objectPendingBody
    }

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
