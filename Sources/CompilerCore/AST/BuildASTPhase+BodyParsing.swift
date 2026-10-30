
extension BuildASTPhase {
    func declarationBody(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        let directTokens = collectDirectTokens(from: nodeID, in: arena)
        let hasExpressionBody = firstTopLevelIndex(
            of: .symbol(.assign), in: directTokens, stoppingAt: .symbol(.lBrace)
        ) != nil

        if !hasExpressionBody {
            for child in arena.children(of: nodeID) {
                if case let .node(childID) = child, arena.node(childID).kind == .block {
                    let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                    return .block(exprs, arena.node(childID).range)
                }
            }
        }

        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = firstTopLevelIndex(of: .symbol(.assign), in: tokens) else {
            return .unit
        }

        let bodyStartIndex = assignIndex + 1
        if bodyStartIndex >= tokens.count {
            return .unit
        }
        let exprTokens = tokens[bodyStartIndex...]
        let parser = ExpressionParser(
            tokens: exprTokens, interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        guard let exprID = parser.parse() else {
            return .unit
        }
        guard let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    private func firstTopLevelIndex(
        of kind: TokenKind, in tokens: [Token], stoppingAt otherKind: TokenKind? = nil
    ) -> Int? {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == kind, depth.isAtTopLevel {
                return index
            }
            if let otherKind, token.kind == otherKind, depth.isAtTopLevel {
                return nil
            }
            depth.track(token.kind)
        }
        return nil
    }

    func blockExpressions(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        excludingNodeIDs: Set<NodeID> = []
    ) -> [ExprID] {
        // The Kotlin CST parser may split `expr\n  .member()` into
        // separate statement nodes, but `.member()` is a continuation
        // of the previous expression, not a standalone statement.
        let groups = collectBlockStatementGroups(
            from: blockNodeID, in: arena, excludingNodeIDs: excludingNodeIDs
        )

        var result: [ExprID] = []
        for group in groups {
            if let exprID = parseStatementGroup(
                raw: group.raw, filtered: group.filtered,
                interner: interner, astArena: astArena
            ) {
                result.append(exprID)
            }
        }
        if result.contains(where: { expression in
            if case .localFunDecl(_, _, _, _, .expr, _, _, _, _) = astArena.expr(expression) { return true }
            return false
        }) {
            let blockTokens = collectTokens(from: blockNodeID, in: arena)
            for expression in result {
                validateLocalFunctionSeparator(after: expression, in: blockTokens, astArena: astArena)
            }
        }
        return result
    }

    private func collectBlockStatementGroups(
        from blockNodeID: NodeID,
        in arena: SyntaxArena,
        excludingNodeIDs: Set<NodeID> = []
    ) -> [(raw: [Token], filtered: [Token])] {
        var groups: [(raw: [Token], filtered: [Token])] = []
        for child in arena.children(of: blockNodeID) {
            guard case let .node(nodeID) = child else { continue }
            let node = arena.node(nodeID)
            guard isStatementLikeKind(node.kind) else { continue }
            // Top-level `fun` declarations at script root are already recorded
            // as real file-scope FunDecls by the caller (see
            // FrontendPhases.buildFileAST); re-parsing them here too would
            // additionally nest them as shadowing local functions inside the
            // synthesized `main()` body.
            if excludingNodeIDs.contains(nodeID) { continue }

            let rawTokens = collectTokens(from: nodeID, in: arena)
            // Strip only top-level semicolons; keep semicolons inside braces so
            // that nested block expressions (e.g. `if (c) { a; b }`) can still
            // split on them later in ExpressionParser.
            // A semicolon inside a loop statement can be its empty body (e.g.
            // `while (condition);`), so loop tokens must reach ExpressionParser
            // intact. Statement separators after a loop are sibling tokens and
            // are not part of this syntax node.
            let filtered = if node.kind == .loopStmt {
                rawTokens
            } else {
                filterTopLevelSemicolons(rawTokens[...])
            }
            guard !filtered.isEmpty else { continue }

            let shouldMergeWithPrevious: Bool
            if let previousFiltered = groups.last?.filtered {
                shouldMergeWithPrevious = Self.isContinuationBoundary(
                    previousTail: previousFiltered, nextHead: filtered[...]
                )
            } else {
                shouldMergeWithPrevious = false
            }
            if shouldMergeWithPrevious {
                groups[groups.count - 1].raw.append(contentsOf: rawTokens)
                groups[groups.count - 1].filtered.append(contentsOf: filtered)
                continue
            }

            groups.append((raw: rawTokens, filtered: filtered))
        }
        return groups
    }

    /// Shared by all three statement-splitting loops in this file and in
    /// `BuildASTPhase+ExpressionParserBlocks.swift`; each loop differs only in
    /// how it iterates (per CST-statement-group, per-token-with-newline, or
    /// per-token-with-explicit-depth-tracking) and in how it gates *when* to
    /// consult this predicate — the merge decision itself lives here once.
    ///
    /// The unclosed-delimiter check only ever fires for the CST-group caller:
    /// the two flat-token callers already gate on bracket-depth zero before
    /// calling this, which makes `previousTail` provably balanced there.
    static func isContinuationBoundary<Prev: BidirectionalCollection, Next: Collection>(
        previousTail: Prev,
        nextHead: Next
    ) -> Bool where Prev.Element == Token, Next.Element == Token {
        guard let last = previousTail.last else {
            return false
        }
        if last.kind == .symbol(.at),
           previousTail.dropLast().last?.kind.isLabelName == true,
           let next = nextHead.first
        {
            switch next.kind {
            case .keyword(.for), .keyword(.while), .keyword(.do):
                return true
            default:
                break
            }
        }
        let lastIndex = previousTail.index(before: previousTail.endIndex)
        let endsWithLabelReference = last.kind.isLabelName
            && lastIndex > previousTail.startIndex
            && previousTail[previousTail.index(before: lastIndex)].kind == .symbol(.at)
        if (!endsWithLabelReference && isStatementContinuationAtLineEnd(last.kind))
            || last.kind == .symbol(.lParen)
            || last.kind == .symbol(.comma)
        {
            return true
        }
        if hasUnclosedStatementDelimiter(previousTail) {
            return true
        }
        // `a or\n    (b)`: Kotlin allows a newline after an infix function
        // name, and `if (a)\n    body`: the branch body may start on the line
        // after the condition. The CST parser splits both at the newline.
        if KotlinParser.endsWithPendingInfixOperator(previousTail)
            || KotlinParser.endsWithControlFlowCondition(previousTail)
            || endsWithUnattachedAnnotation(previousTail)
        {
            return true
        }
        guard let first = nextHead.first else {
            return false
        }
        if first.kind == .keyword(.while), isDoWhileExpressionPrefix(previousTail) {
            return true
        }
        if first.kind.isLabelName,
           nextHead.dropFirst().first?.kind == .symbol(.at) {
            return false
        }
        if ParserBoundaryPolicy.continuesExpressionBeforeNewline(first.kind)
            || first.kind == .symbol(.comma)
            || first.kind == .symbol(.rParen)
            || first.kind == .symbol(.rBracket)
        {
            return true
        }
        if first.kind == .symbol(.assign),
           isDeclarationAssignmentContinuation(previousTail)
        {
            return true
        }
        if first.kind == .symbol(.lBrace), canAcceptTrailingLambda(on: previousTail) {
            return true
        }
        return false
    }

    /// A group ending in an annotation use-site is incomplete: the annotation
    /// attaches to the following expression or declaration, which may start on
    /// the next line (`else @Suppress("UNCHECKED_CAST")` then a newline before
    /// `walk(...)`). Returns true when every top-level token at the tail is an
    /// annotation — `@name`, `@name(args)`, or a chain — so the newline does
    /// not become a statement split.
    ///
    /// `x = @A foo` is not flagged: `foo` already is the operand, so the group
    /// is complete. Label shapes are excluded by the token before `@`:
    /// `return@loop` / `break@x` / `this@Outer` are complete expressions and
    /// `name@` is a label definition, not an annotation.
    private static func endsWithUnattachedAnnotation<C: BidirectionalCollection>(
        _ tokens: C
    ) -> Bool where C.Element == Token {
        var index = tokens.startIndex
        var depth = 0
        var annotationChainStart: C.Index?
        while index < tokens.endIndex {
            let kind = tokens[index].kind
            if depth == 0 {
                if kind == .symbol(.at), !isLabelPosition(before: index, in: tokens),
                   let end = annotationSpanEnd(from: index, in: tokens)
                {
                    if annotationChainStart == nil {
                        annotationChainStart = index
                    }
                    index = end
                    continue
                }
                annotationChainStart = nil
            }
            switch kind {
            case .symbol(.lParen), .symbol(.lBracket), .symbol(.lBrace):
                depth += 1
            case .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace):
                depth = max(0, depth - 1)
            default:
                break
            }
            index = tokens.index(after: index)
        }
        return annotationChainStart != nil
    }

    /// `@` is a label position, not an annotation, when the token before it is
    /// a keyword that takes a label reference (`return@`, `break@`,
    /// `continue@`, `this@`, `super@`) or a bare label name (`loop@`). A name
    /// before `@` that is itself the tail of an annotation (`@A.b` or the
    /// `A` in `@field:A`) instead opens a chained annotation.
    private static func isLabelPosition<C: BidirectionalCollection>(
        before index: C.Index, in tokens: C
    ) -> Bool where C.Element == Token {
        guard index > tokens.startIndex else { return false }
        var scan = tokens.index(before: index)

        // `@A(x)` before a chained annotation: the closer belongs to the
        // previous annotation's argument list — peel the balanced group.
        while true {
            let close = tokens[scan].kind
            let open: TokenKind
            if close == .symbol(.rParen) {
                open = .symbol(.lParen)
            } else if close == .symbol(.rBracket) {
                open = .symbol(.lBracket)
            } else {
                break
            }
            var depth = 0
            var matched = false
            while true {
                let kind = tokens[scan].kind
                if kind == close {
                    depth += 1
                } else if kind == open {
                    depth -= 1
                    if depth == 0 {
                        matched = true
                        break
                    }
                }
                if scan == tokens.startIndex { break }
                scan = tokens.index(before: scan)
            }
            guard matched, scan > tokens.startIndex else { return false }
            scan = tokens.index(before: scan)
        }

        switch tokens[scan].kind {
        case .keyword(.return), .keyword(.break), .keyword(.continue),
             .keyword(.this), .keyword(.super):
            return true
        case let kind where kind.isLabelName || kind == .symbol(.dot):
            // Skip the possibly qualified name backward. Landing on `@` makes
            // it an annotation name, not a label; landing on `:` makes it the
            // name of a use-site-targeted annotation (`@field:A`).
            while tokens[scan].kind.isLabelName || tokens[scan].kind == .symbol(.dot) {
                if scan == tokens.startIndex { return true }
                scan = tokens.index(before: scan)
            }
            if tokens[scan].kind == .symbol(.colon) {
                if scan == tokens.startIndex { return true }
                scan = tokens.index(before: scan)
                while tokens[scan].kind.isLabelName {
                    if scan == tokens.startIndex { return true }
                    scan = tokens.index(before: scan)
                }
            }
            return tokens[scan].kind != .symbol(.at)
        default:
            return false
        }
    }

    /// The index just past the annotation beginning at `at` — `@` plus an
    /// optional use-site target (`name:`), a possibly qualified name, and an
    /// optional `(...)` argument list — or nil when `@` starts none.
    private static func annotationSpanEnd<C: BidirectionalCollection>(
        from at: C.Index, in tokens: C
    ) -> C.Index? where C.Element == Token {
        func isNameToken(_ kind: TokenKind) -> Bool {
            kind.isLabelName
        }
        var index = tokens.index(after: at)
        guard index < tokens.endIndex else { return nil }
        let afterName = tokens.index(after: index)
        if isNameToken(tokens[index].kind),
           afterName < tokens.endIndex,
           tokens[afterName].kind == .symbol(.colon)
        {
            index = tokens.index(after: afterName)
        }
        guard index < tokens.endIndex, isNameToken(tokens[index].kind) else {
            return nil
        }
        index = tokens.index(after: index)
        while index < tokens.endIndex, tokens[index].kind == .symbol(.dot) {
            let afterDot = tokens.index(after: index)
            guard afterDot < tokens.endIndex, isNameToken(tokens[afterDot].kind) else {
                return index
            }
            index = tokens.index(after: afterDot)
        }
        guard index < tokens.endIndex, tokens[index].kind == .symbol(.lParen) else {
            return index
        }
        var depth = 0
        while index < tokens.endIndex {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                depth += 1
            } else if kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    return tokens.index(after: index)
                }
            }
            index = tokens.index(after: index)
        }
        return nil
    }

    /// A newline before `while` keeps it attached to a preceding do-loop body.
    private static func isDoWhileExpressionPrefix<C: BidirectionalCollection>(
        _ tokens: C
    ) -> Bool where C.Element == Token {
        var index = tokens.startIndex
        while index < tokens.endIndex {
            guard tokens[index].kind.isLabelName else { break }
            let afterName = tokens.index(after: index)
            guard afterName < tokens.endIndex,
                  tokens[afterName].kind == .symbol(.at)
            else {
                break
            }
            index = tokens.index(after: afterName)
        }
        return index < tokens.endIndex && tokens[index].kind == .keyword(.do)
    }

    private static func isDeclarationAssignmentContinuation<C: Collection>(_ tokens: C) -> Bool where C.Element == Token {
        var depth = BracketDepth()
        var sawDeclaration = false
        for token in tokens {
            if depth.isBracketBraceParenTopLevel {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) { return false }
                switch token.kind {
                case .keyword(.fun), .keyword(.val), .keyword(.var):
                    sawDeclaration = true
                default:
                    break
                }
            }
            depth.track(token.kind)
        }
        return sawDeclaration
    }

    func filterTopLevelSemicolons(_ tokens: ArraySlice<Token>) -> [Token] {
        var result: [Token] = []
        result.reserveCapacity(tokens.count)
        var braceDepth = 0
        for token in tokens {
            switch token.kind {
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            default: break
            }
            if token.kind == .symbol(.semicolon), braceDepth == 0 {
                continue
            }
            result.append(token)
        }
        return result
    }

    private static func hasUnclosedStatementDelimiter<C: Collection>(_ tokens: C) -> Bool where C.Element == Token {
        var depth = BracketDepth()
        for token in tokens {
            depth.track(token.kind)
        }
        // Deliberately ignores `depth.angle`: an unmatched `<`/`>` from a
        // generic or comparison in the previous group must not affect the
        // merge decision, unlike `BracketDepth.isAtTopLevel`.
        return depth.paren > 0 || depth.bracket > 0 || depth.brace > 0
    }

    /// Whether a `{` that starts the next statement line continues the
    /// previous group. Kotlin only attaches such a block when the previous
    /// tokens still expect a body — a declaration or literal header
    /// (`fun f(): Int`, `object : I`, `class C`) or a keyword whose grammar
    /// production is a braced body (`try`, `do`, subject-less `when`,
    /// `init`, `suspend` for a suspending lambda literal) — or when they
    /// end in an explicit call suffix (`name(…)` or
    /// `name<…>`), as in `run()` + `{ }`. (`else`/`catch`/`finally` tails and
    /// `x is T`-style operator tails merge earlier in
    /// `isContinuationBoundary`, so they never reach this check.)
    ///
    /// A bare name or value (`Unit`, `x`, `a[i]`, `(x)`, `x!!`, `return`) is
    /// a complete expression: the block starts a new statement instead of
    /// becoming a call argument, so `val tmp = Unit` followed by `{ }` never
    /// resolves as `Unit { }` (KUU-3144).
    static func canAcceptTrailingLambda<C: BidirectionalCollection>(on tokens: C) -> Bool where C.Element == Token {
        if isLocalPropertyDeclarationEndingWithName(tokens) {
            return false
        }
        guard let last = tokens.last else {
            return false
        }
        if hasPendingBracedBodyHeader(tokens) {
            return true
        }
        switch last.kind {
        case .symbol(.rParen):
            return endsWithCallArgumentList(tokens)
        case .symbol(.greaterThan):
            return endsWithNameTypeArguments(tokens)
        case .keyword(.try), .keyword(.do), .keyword(.when),
             .keyword(.suspend), .softKeyword(.`init`):
            return true
        default:
            return false
        }
    }

    /// Whether the group is a header whose `{ }` body has not opened yet: a
    /// local `fun`/`class`/`object`/`interface` declaration or an
    /// `object : T` / `fun () : T` literal with its body on the next line.
    /// The keyword must sit at the group's top level — a `fun`/`object`
    /// inside a call's parentheses is part of a nested expression, not a
    /// header awaiting its body.
    private static func hasPendingBracedBodyHeader<C: Collection>(_ tokens: C) -> Bool where C.Element == Token {
        var depth = BracketDepth()
        var awaitsBody = false
        for token in tokens {
            if depth.isBracketBraceParenTopLevel {
                switch token.kind {
                case .keyword(.fun), .keyword(.object), .keyword(.class), .keyword(.interface):
                    awaitsBody = true
                case .symbol(.lBrace):
                    // A body block already opened at this level, so the
                    // header is complete and a later `{` is a new statement.
                    awaitsBody = false
                default:
                    break
                }
            }
            depth.track(token.kind)
        }
        return awaitsBody
    }

    /// Whether the group's last `)` closes a call's value-argument list: the
    /// matching `(` directly follows a callee (`name(`, `f<T>(`, `a[i](`,
    /// `f()(`, `{ }(`). A parenthesized expression (`(x)`, `= (x)`) and a
    /// control-flow condition (`if (x)`) have no callee before their `(`, so
    /// a `{` on the next line cannot be a trailing lambda there.
    private static func endsWithCallArgumentList<C: BidirectionalCollection>(_ tokens: C) -> Bool where C.Element == Token {
        var depth = 0
        var index = tokens.index(before: tokens.endIndex)
        while true {
            switch tokens[index].kind {
            case .symbol(.rParen):
                depth += 1
            case .symbol(.lParen):
                depth -= 1
                if depth == 0 {
                    guard index > tokens.startIndex else { return false }
                    switch tokens[tokens.index(before: index)].kind {
                    case .identifier, .backtickedIdentifier, .softKeyword,
                         .symbol(.rParen), .symbol(.rBracket), .symbol(.rBrace),
                         .symbol(.greaterThan):
                        return true
                    default:
                        return false
                    }
                }
            default:
                break
            }
            if index == tokens.startIndex { return false }
            index = tokens.index(before: index)
        }
    }

    /// Whether the group ends in a type-argument list applied to a callee
    /// (`name<T>`): the `<` matching the trailing `>` directly follows a
    /// name. A comparison `x < y >` has no such receiver-free shape, so its
    /// `>` does not accept a trailing lambda on the next line.
    private static func endsWithNameTypeArguments<C: BidirectionalCollection>(_ tokens: C) -> Bool where C.Element == Token {
        var depth = 0
        var index = tokens.index(before: tokens.endIndex)
        while true {
            switch tokens[index].kind {
            case .symbol(.greaterThan):
                depth += 1
            case .symbol(.lessThan):
                depth -= 1
                if depth == 0 {
                    guard index > tokens.startIndex else { return false }
                    switch tokens[tokens.index(before: index)].kind {
                    case .identifier, .backtickedIdentifier, .softKeyword,
                         .symbol(.greaterThan):
                        return true
                    default:
                        return false
                    }
                }
            default:
                break
            }
            if index == tokens.startIndex { return false }
            index = tokens.index(before: index)
        }
    }

    /// A local property declaration ending in a name is complete before a
    /// lambda on the following line. A call-shaped initializer ending in `)`
    /// can still take a trailing lambda across the newline.
    private static func isLocalPropertyDeclarationEndingWithName<C: BidirectionalCollection>(
        _ tokens: C
    ) -> Bool where C.Element == Token {
        var depth = BracketDepth()
        var sawLocalProperty = false
        var awaitsObjectBody = false
        for token in tokens {
            if depth.isBracketBraceParenTopLevel {
                if token.kind == .keyword(.val) || token.kind == .keyword(.var) {
                    sawLocalProperty = true
                }
                if token.kind == .keyword(.object) {
                    awaitsObjectBody = true
                } else if token.kind == .symbol(.lBrace) {
                    awaitsObjectBody = false
                }
            }
            depth.track(token.kind)
        }
        guard sawLocalProperty, !awaitsObjectBody, let last = tokens.last else {
            return false
        }
        switch last.kind {
        case .identifier, .backtickedIdentifier, .softKeyword:
            return true
        default:
            return false
        }
    }

    /// Shared by the CST-driven top-level path (blockExpressions) and the
    /// token-driven local-function-body path (parseBraceBody in
    /// BuildASTPhase+LocalFunParsing.swift) so both dispatch identically.
    func parseStatementGroup(
        raw: [Token],
        filtered: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        // Local nominals retain header annotations for declaration validation.
        // Local fun/val dispatch needs the stripped view to see the head
        // keyword. Assignment and expression statements keep the unstripped
        // head so leading annotations still attach to the parsed expression —
        // dropping them would also drop unresolved-annotation diagnostics.
        //
        // Every probe is speculative: a failing attempt (e.g. an assignment
        // scan that parses `do x` as a compound-assign LHS) can emit
        // diagnostics for a parse the group is then reparsed without. Roll
        // those back; only the winning parse keeps its diagnostics.
        let speculationCheckpoint = diagnostics?.checkpoint()
        func undoFailedSpeculation() {
            if let speculationCheckpoint {
                diagnostics?.rollback(to: speculationCheckpoint)
            }
        }
        if let expr = Self.parseLocalNominalDeclExpr(
            from: raw, interner: interner, astArena: astArena, diagnostics: diagnostics
        ) {
            return expr
        }
        undoFailedSpeculation()
        // Local fun parsing strips leading annotations itself so it can attach
        // declaration-level `@Suppress` to the produced declaration.
        let strippedFiltered = Self.skipLeadingLocalAnnotations(filtered, interner: interner)
        if let expr = parseLocalFunDeclExpr(from: raw, interner: interner, astArena: astArena) {
            return expr
        }
        undoFailedSpeculation()
        if let expr = parseLocalDeclarationExpr(from: strippedFiltered, interner: interner, astArena: astArena) {
            return expr
        }
        undoFailedSpeculation()
        if let expr = parseLocalAssignmentExpr(from: filtered, interner: interner, astArena: astArena) {
            return expr
        }
        undoFailedSpeculation()
        let parser = ExpressionParser(
            tokens: filtered, interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        return parser.parse()
    }

    func splitTokensIntoStatements(_ tokens: [Token]) -> [[Token]] {
        var groups: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for (idx, token) in tokens.enumerated() {
            if depth.isBracketBraceParenTopLevel {
                if token.kind == .symbol(.semicolon) {
                    if !current.isEmpty {
                        groups.append(current)
                        current = []
                    }
                    continue
                }
                let hasNewline = token.leadingTrivia.contains { piece in
                    if case .newline = piece { return true }
                    return false
                }
                if hasNewline, !current.isEmpty,
                   !Self.isContinuationBoundary(previousTail: current, nextHead: tokens[idx...])
                {
                    groups.append(current)
                    current = []
                }
            }
            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    static func isBinaryOperatorToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.plus), .symbol(.minus), .symbol(.star), .symbol(.slash), .symbol(.percent),
             .symbol(.ampAmp), .symbol(.barBar),
             .symbol(.equalEqual), .symbol(.bangEqual),
             .symbol(.lessThan), .symbol(.lessOrEqual), .symbol(.greaterThan), .symbol(.greaterOrEqual),
             .symbol(.assign), .symbol(.plusAssign), .symbol(.minusAssign),
             .symbol(.starAssign), .symbol(.slashAssign), .symbol(.percentAssign),
             .symbol(.dotDot), .symbol(.dotDotLt),
             .symbol(.questionQuestion), .symbol(.questionColon),
             .symbol(.dot), .symbol(.questionDot),
             .symbol(.doubleColon),
             .symbol(.arrow), .symbol(.fatArrow),
             .keyword(.as), .keyword(.is), .keyword(.in),
             .keyword(.else), .keyword(.catch), .keyword(.finally):
            true
        default:
            false
        }
    }

    /// A closing `>` can be either a binary comparison operator or the end of
    /// a generic type argument list. At a line ending it completes the latter,
    /// so it must not merge the following statement into the current group.
    static func isStatementContinuationAtLineEnd(_ kind: TokenKind) -> Bool {
        switch kind {
        case .symbol(.greaterThan):
            return false
        default:
            return isBinaryOperatorToken(kind)
        }
    }

    func skipBalancedBracket(
        in tokens: [Token],
        from startIndex: Int,
        open: TokenKind,
        close: TokenKind
    ) -> Int {
        guard startIndex < tokens.count, tokens[startIndex].kind == open else {
            return startIndex
        }
        var depth = 0
        var index = startIndex
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == open {
                depth += 1
            } else if kind == close {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            }
            index += 1
        }
        return index
    }

    func resolveToken(_ tokenID: TokenID, in arena: SyntaxArena) -> Token? {
        guard let token = arena.token(tokenID) else { return nil }
        // Honor a recovered closing parenthesis so malformed annotation
        // arguments cannot hide a following declaration during AST scans.
        if case .missing(expected: .symbol(.rParen)) = token.kind {
            return Token(kind: .symbol(.rParen), range: token.range)
        }
        return token
    }

    func collectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        if let cached = tokenCache[nodeID] {
            return cached
        }
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case let .token(tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    tokens.append(token)
                }
            case let .node(childID):
                tokens.append(contentsOf: collectTokens(from: childID, in: arena))
            }
        }
        tokenCache[nodeID] = tokens
        return tokens
    }

    func collectDirectTokens(from nodeID: NodeID, in arena: SyntaxArena) -> [Token] {
        var tokens: [Token] = []
        for child in arena.children(of: nodeID) {
            guard case let .token(tokenID) = child,
                  let token = resolveToken(tokenID, in: arena)
            else {
                continue
            }
            tokens.append(token)
        }
        return tokens
    }

    func isStatementLikeKind(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .statement, .propertyDecl, .loopStmt,
             .ifExpr, .whenExpr, .tryExpr, .callExpr,
             .funDecl, .classDecl, .objectDecl, .interfaceDecl,
             .typeAliasDecl:
            true
        default:
            false
        }
    }

    func declarationAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        annotationsFromTokens(collectTokens(from: nodeID, in: arena), interner: interner)
    }

    /// Used when annotations may be in sibling
    /// tokens preceding the declaration node in the CST.
    func annotationsFromTokens(_ tokens: [Token], interner: StringInterner) -> [AnnotationNode] {
        var annotations: [AnnotationNode] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if isDeclarationStart(token.kind) { break }
            guard token.kind == .symbol(.at) else { index += 1; continue }
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: tokens, start: index, interner: interner, allowUseSiteTarget: true
            ) else { index += 1; continue }
            annotations.append(parsed.annotation)
            index = parsed.nextIndex
        }
        return annotations
    }

    /// Local fun/val declaration dispatch needs the stripped view to see the
    /// head keyword; assignment and expression statements keep the head so
    /// leading annotations still attach to the parsed expression.
    static func skipLeadingLocalAnnotations(_ tokens: [Token], interner: StringInterner) -> [Token] {
        var index = 0
        while index < tokens.count, tokens[index].kind == .symbol(.at) {
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: tokens, start: index, interner: interner, allowUseSiteTarget: true
            ) else {
                break
            }
            index = parsed.nextIndex
        }
        return index == 0 ? tokens : Array(tokens[index...])
    }

    /// Local declaration dispatch consumes leading labels as part of the statement.
    /// Strip them only on the declaration path so expression labels remain intact.
    static func skipLeadingLocalDeclarationLabels(_ tokens: [Token]) -> [Token] {
        var index = 0
        while index + 1 < tokens.count,
              tokens[index].kind.isLabelName,
              tokens[index + 1].kind == .symbol(.at)
        {
            index += 2
        }
        return index == 0 ? tokens : Array(tokens[index...])
    }

    private func isDeclarationStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.class), .keyword(.object), .keyword(.interface),
             .keyword(.fun), .keyword(.val), .keyword(.var),
             .keyword(.typealias), .keyword(.enum), .keyword(.companion),
             .keyword(.constructor), .softKeyword(.constructor):
            true
        default:
            false
        }
    }
}
