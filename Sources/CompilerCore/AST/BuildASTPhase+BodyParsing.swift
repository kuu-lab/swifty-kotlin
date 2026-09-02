
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
        let parser = ExpressionParser(tokens: exprTokens, interner: interner, astArena: astArena)
        guard let exprID = parser.parse() else {
            return .unit
        }
        guard let range = astArena.exprRange(exprID) else {
            return .unit
        }
        return .expr(exprID, range)
    }

    /// Returns the index of the first token matching `kind` at bracket-top-level,
    /// or `nil` if `stoppingAt` is reached at top-level first (or if neither is
    /// found).
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
        // Phase 1 – gather per-CST-statement token groups, merging
        // dot-continuation lines into the previous group.
        // The Kotlin CST parser may split `expr\n  .member()` into
        // separate statement nodes, but `.member()` is a continuation
        // of the previous expression, not a standalone statement.
        let groups = collectBlockStatementGroups(
            from: blockNodeID, in: arena, excludingNodeIDs: excludingNodeIDs
        )

        // Phase 2 – parse each (potentially merged) token group.
        var result: [ExprID] = []
        for group in groups {
            if let exprID = parseStatementGroup(
                raw: group.raw, filtered: group.filtered,
                interner: interner, astArena: astArena
            ) {
                result.append(exprID)
            }
        }
        return result
    }

    /// Collect token groups from CST block children, merging dot-continuation
    /// lines (`.member()`) into the previous statement group.
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
            let filtered = filterTopLevelSemicolons(rawTokens[...])
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

    /// Decides whether `nextHead` (the start of a candidate new statement)
    /// is actually a continuation of `previousTail` (the tokens accumulated
    /// so far for the previous statement) rather than the start of a new one.
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
        if isStatementContinuationAtLineEnd(last.kind)
            || last.kind == .symbol(.lParen)
            || last.kind == .symbol(.comma)
        {
            return true
        }
        if hasUnclosedStatementDelimiter(previousTail) {
            return true
        }
        guard let first = nextHead.first else {
            return false
        }
        // `isBinaryOperatorToken` already covers `.`/`?.`, so a dot-continuation
        // line (`.member()`) is a continuation via this check too.
        if isBinaryOperatorToken(first.kind)
            || first.kind == .symbol(.comma)
            || first.kind == .symbol(.rParen)
            || first.kind == .symbol(.rBracket)
        {
            return true
        }
        if first.kind == .symbol(.lBrace), canAcceptTrailingLambda(on: previousTail) {
            return true
        }
        return false
    }

    /// Filter out semicolons that are at the outermost brace level,
    /// preserving those inside nested braces (e.g. lambda bodies).
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

    static func canAcceptTrailingLambda<C: BidirectionalCollection>(on tokens: C) -> Bool where C.Element == Token {
        guard let last = tokens.last else {
            return false
        }
        if let first = tokens.first,
           case let .keyword(keyword) = first.kind,
           [.if, .for, .while, .do, .when, .try, .catch, .finally].contains(keyword)
        {
            return false
        }
        switch last.kind {
        case .identifier, .backtickedIdentifier, .softKeyword, .keyword:
            return true
        case .symbol(.rParen), .symbol(.rBracket), .symbol(.greaterThan), .symbol(.bangBang):
            return true
        default:
            return false
        }
    }

    /// Parse a single (possibly merged) statement token group, trying local
    /// fun-decl, local-decl, local-assign, then generic expression.
    ///
    /// Shared by the CST-driven top-level path (blockExpressions) and the
    /// token-driven local-function-body path (parseBraceBody in
    /// BuildASTPhase+LocalFunParsing.swift) so both dispatch identically.
    func parseStatementGroup(
        raw: [Token],
        filtered: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let raw = skipLeadingLocalAnnotations(raw, interner: interner)
        let filtered = skipLeadingLocalAnnotations(filtered, interner: interner)
        if let expr = parseLocalFunDeclExpr(from: raw, interner: interner, astArena: astArena) {
            return expr
        }
        if let expr = parseLocalDeclarationExpr(from: filtered, interner: interner, astArena: astArena) {
            return expr
        }
        if let expr = parseLocalAssignmentExpr(from: filtered, interner: interner, astArena: astArena) {
            return expr
        }
        let parser = ExpressionParser(tokens: filtered, interner: interner, astArena: astArena)
        return parser.parse()
    }

    func splitTokensIntoStatements(_ tokens: [Token]) -> [[Token]] {
        var groups: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for (idx, token) in tokens.enumerated() {
            if depth.isAtTopLevel {
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
        arena.token(tokenID)
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
             .funDecl:
            true
        default:
            false
        }
    }

    // MARK: - Annotation Parsing

    // Extracts annotation nodes from the leading tokens of a declaration CST node.
    // Annotations appear as `@Name` or `@Name(args)` tokens before the declaration
    // keyword (class, fun, val, var, etc.).  Also handles use-site targets like
    // `@get:Name` or `@field:Name(args)`.
    func declarationAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        annotationsFromTokens(collectTokens(from: nodeID, in: arena), interner: interner)
    }

    /// Parses leading annotations from an arbitrary token array, stopping at a
    /// declaration introducer keyword. Used when annotations may be in sibling
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

    /// Skips leading annotation tokens (`@Name`, `@Name(...)`, optionally with
    /// a use-site target) from a local statement's token list. Local
    /// statements have no AST representation for annotations, so callers that
    /// dispatch on a statement's leading keyword must strip them first —
    /// otherwise a leading `@` token is unrecognized by every local-statement
    /// parser (and by the generic `ExpressionParser` fallback), silently
    /// dropping the entire statement.
    func skipLeadingLocalAnnotations(_ tokens: [Token], interner: StringInterner) -> [Token] {
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

    /// Checks if a token represents a declaration start keyword.
    private func isDeclarationStart(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.class), .keyword(.object), .keyword(.interface),
             .keyword(.fun), .keyword(.val), .keyword(.var),
             .keyword(.typealias), .keyword(.enum), .keyword(.companion):
            true
        default:
            false
        }
    }
}
