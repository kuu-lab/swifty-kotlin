
extension BuildASTPhase {
    func declarationPropertyName(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        var sawValOrVar = false
        for token in tokens {
            switch token.kind {
            case .keyword(.val), .keyword(.var):
                sawValOrVar = true
                continue
            default:
                break
            }
            guard sawValOrVar,
                  let name = internedIdentifier(from: token, interner: interner)
            else {
                continue
            }
            return name
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationIsVar(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        for child in arena.children(of: nodeID) {
            if case let .token(tokenID) = child,
               let token = resolveToken(tokenID, in: arena),
               token.kind == .keyword(.var)
            {
                return true
            }
        }
        return false
    }

    func declarationPropertyInitializer(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena, includingTrailingLambdaTokens: true)
        guard !tokens.isEmpty else {
            return nil
        }

        var assignIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                return nil
            }
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
                assignIndex = index
                break
            }
            depth.track(token.kind)
        }

        guard let assignIndex else {
            return nil
        }
        let start = assignIndex + 1
        guard start < tokens.count else {
            return nil
        }
        let exprTokens = filterTopLevelSemicolons(tokens[start...])
        guard !exprTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(
            tokens: exprTokens[...], interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        return parser.parse()
    }

    func declarationPropertyAccessors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?

        // First, try to find accessors inside a block child (e.g. `val x: T { get() = ... }`).
        if let accessorBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first {
            // An inline `get() { ... }` may leave the accessor header on the
            // property and its body as a sibling block. It is not a property
            // accessor container in that case.
            let directTokens = collectDirectTokens(from: nodeID, in: arena)
            var foundSiblingBlockAccessor = false
            if inlineAccessorStartIndex(in: directTokens, bodyIsSiblingBlock: true) != nil {
                // Several inline accessors may share the line, e.g.
                // `var p: Int get() { ... } set(v) { ... }`: each accessor
                // owns the header tokens and sibling blocks up to the next one.
                let siblingResult = siblingBlockAccessors(
                    from: nodeID, in: arena, interner: interner, astArena: astArena
                )
                getter = siblingResult.getter
                setter = siblingResult.setter
                foundSiblingBlockAccessor = getter != nil || setter != nil
            }
            if !foundSiblingBlockAccessor {
                for child in arena.children(of: accessorBlockID) {
                    processAccessorChild(
                        child,
                        in: arena,
                        interner: interner,
                        astArena: astArena,
                        getter: &getter,
                        setter: &setter
                    )
                }
                return (getter, setter)
            }
        }

        // Check for propertyAccessor nodes (structured inline accessor syntax).
        // When the parser wraps accessor tokens in .propertyAccessor nodes we
        // can collect them reliably without flat-token scanning.
        // If a propertyAccessor contains a .block child (e.g. `set(v) { ... }`),
        // process it directly using accessorBody which handles block bodies correctly.
        // Skip propertyAccessor nodes that represent explicit backing fields
        // (`field = expr` or `field: Type = expr`) — those are handled by
        // `declarationExplicitBackingField`.
        var hasAccessorNode = false
        for child in arena.children(of: nodeID) {
            if case let .node(childID) = child,
               arena.node(childID).kind == .propertyAccessor
            {
                // Skip explicit backing field nodes (start with `field` soft keyword).
                let firstToken = collectTokens(from: childID, in: arena).first
                if let firstToken, case .softKeyword(.field) = firstToken.kind {
                    continue
                }
                hasAccessorNode = true
                let hasBlock = arena.children(of: childID).contains { child in
                    if case let .node(grandchildID) = child {
                        return arena.node(grandchildID).kind == .block
                    }
                    return false
                }
                if hasBlock {
                    processPropertyAccessorWithBlock(
                        childID,
                        in: arena,
                        interner: interner,
                        astArena: astArena,
                        getter: &getter,
                        setter: &setter
                    )
                } else {
                    let result = parseInlineAccessors(
                        from: collectTokens(from: childID, in: arena),
                        nodeRange: arena.node(childID).range,
                        interner: interner, astArena: astArena
                    )
                    if getter == nil { getter = result.getter }
                    if setter == nil { setter = result.setter }
                }
            }
        }
        if hasAccessorNode {
            // A semicolon can split accessors asymmetrically: the first inline
            // accessor remains as direct tokens on the property node while a
            // following accessor is wrapped in its own `.propertyAccessor`
            // child. Parse that direct-token prefix as well, otherwise a
            // `var` with `get() ...; set(...) ...` loses its getter entirely.
            let directTokens = collectDirectTokens(from: nodeID, in: arena)
            if inlineAccessorStartIndex(in: directTokens) != nil {
                let directAccessorTokens = directTokens
                let directResult = parseInlineAccessors(
                    from: directAccessorTokens,
                    nodeRange: arena.node(nodeID).range,
                    interner: interner,
                    astArena: astArena
                )
                if getter == nil { getter = directResult.getter }
                if setter == nil { setter = directResult.setter }
            }
            return (getter, setter)
        }

        // Fallback: detect inline accessor syntax from flat tokens.
        // Handles `val x: T get() = expr` where get()/set() appear as flat
        // tokens of the property node without a wrapping block.
        if getter != nil || setter != nil {
            return (getter, setter)
        }
        let allTokens = collectTokens(from: nodeID, in: arena)
        return parseInlineAccessors(from: allTokens, nodeRange: arena.node(nodeID).range, interner: interner, astArena: astArena)
    }

    /// Find the index where an inline `get`/`set` accessor keyword starts in
    /// a flat token list.  Returns `nil` when no accessor keyword is present.
    /// - Parameter bodyIsSiblingBlock: the accessor's `{ ... }` body is a separate
    ///   block node, so the direct tokens legitimately end after the header.
    func inlineAccessorStartIndex(in tokens: [Token], bodyIsSiblingBlock: Bool = false) -> Int? {
        for (index, token) in tokens.enumerated() {
            let isAccessorKeyword = switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                true
            default:
                false
            }
            guard isAccessorKeyword else { continue }
            // Require `(` immediately after to distinguish from identifiers.
            guard index + 1 < tokens.count,
                  tokens[index + 1].kind == .symbol(.lParen)
            else {
                continue
            }
            // A member call such as `lookup.get(...)` or `lookup?.set(...)`
            // uses the same soft-keyword spelling as an inline accessor.
            if index > 0 {
                switch tokens[index - 1].kind {
                case .symbol(.dot), .symbol(.questionDot):
                    continue
                default:
                    break
                }
            }
            // Inline accessors have a declaration body after their parameter
            // list. An accessor may optionally declare its return type before
            // the body, as in `get(): Int = value`.
            let afterClose = skipBalancedBracket(
                in: tokens,
                from: index + 1,
                open: .symbol(.lParen),
                close: .symbol(.rParen)
            )
            guard afterClose > index + 1 else {
                continue
            }
            var bodyStart = afterClose
            if bodyStart < tokens.count, tokens[bodyStart].kind == .symbol(.colon) {
                bodyStart += 1
                var typeDepth = BracketDepth()
                while bodyStart < tokens.count {
                    if typeDepth.isAtTopLevel {
                        switch tokens[bodyStart].kind {
                        case .symbol(.assign), .symbol(.lBrace):
                            break
                        default:
                            typeDepth.track(tokens[bodyStart].kind)
                            bodyStart += 1
                            continue
                        }
                        break
                    }
                    typeDepth.track(tokens[bodyStart].kind)
                    bodyStart += 1
                }
            }
            guard bodyStart < tokens.count else {
                if bodyIsSiblingBlock { return index }
                continue
            }
            switch tokens[bodyStart].kind {
            case .symbol(.assign), .symbol(.lBrace):
                return index
            default:
                continue
            }
        }
        return nil
    }

    /// Keep only an annotation prefix immediately preceding the accessor.
    /// Earlier property annotations and annotations inside an initializer are
    /// not accessor annotations.
    private func accessorAnnotations(from tokens: [Token], interner: StringInterner) -> [AnnotationNode] {
        for start in tokens.indices where tokens[start].kind == .symbol(.at) {
            var index = start
            var annotations: [AnnotationNode] = []
            while index < tokens.count, tokens[index].kind == .symbol(.at),
                  let parsed = AnnotationParsingSupport.parseAnnotation(
                      from: tokens, start: index, interner: interner, allowUseSiteTarget: true
                  ) {
                annotations.append(parsed.annotation)
                index = parsed.nextIndex
            }
            if index == tokens.count { return annotations }
        }
        return []
    }

    /// Parse inline `get()/set()` accessor declarations from a flat token
    /// stream.  For `val x: T get() = expr`, the tokens after the type
    /// annotation contain `get ( ) = expr` without a wrapping block node.
    private func parseInlineAccessors(
        from allTokens: [Token],
        nodeRange: SourceRange,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        var remaining = allTokens[...]

        while let startIdx = remaining.firstIndex(where: { token in
            switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                true
            default:
                false
            }
        }) {
            let annotations = accessorAnnotations(from: Array(remaining[..<startIdx]), interner: interner)
            let token = remaining[startIdx]
            let kind: PropertyAccessorKind
            switch token.kind {
            case .softKeyword(.get): kind = .getter
            case .softKeyword(.set): kind = .setter
            default:
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            // Require `(` immediately after the keyword.
            guard startIdx + 1 < remaining.endIndex,
                  remaining[startIdx + 1].kind == .symbol(.lParen)
            else {
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            // Find matching `)` after `(`.
            var closeParenIdx = startIdx + 2
            var depth = 1
            while closeParenIdx < remaining.endIndex {
                if remaining[closeParenIdx].kind == .symbol(.lParen) { depth += 1 }
                if remaining[closeParenIdx].kind == .symbol(.rParen) {
                    depth -= 1
                    if depth == 0 { break }
                }
                closeParenIdx += 1
            }
            guard closeParenIdx < remaining.endIndex else {
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            let parameterName: InternedString?
            if kind == .setter {
                let parenTokens = Array(remaining[(startIdx + 1) ... closeParenIdx])
                parameterName = setterParameterName(from: parenTokens, interner: interner)
            } else {
                parameterName = nil
            }

            // Determine accessor body: either `= expr` or `{ block }`, with
            // an optional explicit return type between `)` and the body.
            var afterParen = closeParenIdx + 1
            if afterParen < remaining.endIndex,
               remaining[afterParen].kind == .symbol(.colon)
            {
                afterParen += 1
                var typeDepth = BracketDepth()
                while afterParen < remaining.endIndex {
                    if typeDepth.isAtTopLevel {
                        switch remaining[afterParen].kind {
                        case .symbol(.assign), .symbol(.lBrace):
                            break
                        default:
                            typeDepth.track(remaining[afterParen].kind)
                            afterParen += 1
                            continue
                        }
                        break
                    }
                    typeDepth.track(remaining[afterParen].kind)
                    afterParen += 1
                }
            }
            let body: FunctionBody
            if afterParen < remaining.endIndex,
               remaining[afterParen].kind == .symbol(.assign)
            {
                // Find extent of body expression: up to the next get/set keyword or end.
                // A `get`/`set` soft keyword only opens the next accessor when it
                // starts an accessor header: at top level, followed by `(`, and
                // not preceded by a navigation operator. Member-call tokens like
                // `this.get()` or a `get(` nested inside call arguments or a
                // lambda are part of the body expression, not a boundary.
                let exprStart = afterParen + 1
                var exprEnd = remaining.endIndex
                var bodyDepth = BracketDepth()
                for i in exprStart ..< remaining.endIndex {
                    let token = remaining[i]
                    switch token.kind {
                    case .softKeyword(.get), .softKeyword(.set):
                        // Check if it's followed by `(` to confirm it's an accessor keyword.
                        let precededByNavigation = i > exprStart
                            && (remaining[i - 1].kind == .symbol(.dot)
                                || remaining[i - 1].kind == .symbol(.questionDot)
                                || remaining[i - 1].kind == .symbol(.doubleColon))
                        if bodyDepth.isAtTopLevel,
                           !precededByNavigation,
                           i + 1 < remaining.endIndex,
                           remaining[i + 1].kind == .symbol(.lParen)
                        {
                            exprEnd = i
                        }
                    default:
                        break
                    }
                    if exprEnd != remaining.endIndex { break }
                    bodyDepth.track(token.kind)
                }
                let exprTokens = Array(remaining[exprStart ..< exprEnd])
                if !exprTokens.isEmpty {
                    let parser = ExpressionParser(
                        tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena,
                        diagnostics: diagnostics
                    )
                    if let exprID = parser.parse(),
                       let range = astArena.exprRange(exprID)
                    {
                        body = .expr(exprID, range)
                    } else {
                        body = .unit
                    }
                } else {
                    body = .unit
                }
                remaining = remaining[exprEnd...]
            } else if afterParen < remaining.endIndex,
                      remaining[afterParen].kind == .symbol(.lBrace)
            {
                // Block body: `set(v) { ... }` or `get() { ... }`
                var depth = 1
                var braceEnd = afterParen + 1
                while braceEnd < remaining.endIndex, depth > 0 {
                    if remaining[braceEnd].kind == .symbol(.lBrace) { depth += 1 }
                    if remaining[braceEnd].kind == .symbol(.rBrace) { depth -= 1 }
                    braceEnd += 1
                }
                // Parse the braces as a statement block: a single-expression
                // parse would keep only the first of `{ a(); b = v }`'s
                // statements and silently drop the rest.
                let blockTokens = Array(remaining[afterParen ..< braceEnd])
                if let blockExprID = ExpressionParser(
                    tokens: ArraySlice(blockTokens), interner: interner, astArena: astArena,
                    diagnostics: diagnostics
                ).parseBlockExpression(),
                    case let .blockExpr(statements, trailingExpr, blockRange)? = astArena.expr(blockExprID)
                {
                    body = .block(statements + (trailingExpr.map { [$0] } ?? []), blockRange)
                } else {
                    body = .unit
                }
                remaining = remaining[braceEnd...]
            } else {
                body = .unit
                remaining = remaining[afterParen...]
            }

            let accessor = PropertyAccessorDecl(
                range: nodeRange,
                kind: kind,
                annotations: annotations,
                parameterName: parameterName,
                body: body
            )
            switch kind {
            case .getter:
                if getter == nil { getter = accessor }
            case .setter:
                if setter == nil { setter = accessor }
            }
        }

        return (getter, setter)
    }

    private func processPropertyAccessorWithBlock(
        _ accessorNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        getter: inout PropertyAccessorDecl?,
        setter: inout PropertyAccessorDecl?
    ) {
        let rawHeaderTokens = collectDirectTokens(from: accessorNodeID, in: arena).filter { token in
            token.kind != .symbol(.semicolon)
        }
        let annotations = annotationsFromTokens(rawHeaderTokens, interner: interner)
        guard let accessorStart = inlineAccessorStartIndex(in: rawHeaderTokens, bodyIsSiblingBlock: true) else { return }
        let headerTokens = Array(rawHeaderTokens[accessorStart...])
        guard let firstToken = headerTokens.first else { return }

        let kind: PropertyAccessorKind
        switch firstToken.kind {
        case .softKeyword(.get): kind = .getter
        case .softKeyword(.set): kind = .setter
        default: return
        }

        let parameterName: InternedString? = kind == .setter
            ? setterParameterName(from: headerTokens, interner: interner)
            : nil

        let body = accessorBody(
            statementID: accessorNodeID,
            headerTokens: headerTokens,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let accessor = PropertyAccessorDecl(
            range: arena.node(accessorNodeID).range,
            kind: kind,
            annotations: annotations,
            parameterName: parameterName,
            body: body
        )
        switch kind {
        case .getter: if getter == nil { getter = accessor }
        case .setter: if setter == nil { setter = accessor }
        }
    }

    private func processAccessorChild(
        _ child: SyntaxChild,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        getter: inout PropertyAccessorDecl?,
        setter: inout PropertyAccessorDecl?
    ) {
        guard case let .node(statementID) = child,
              isStatementLikeKind(arena.node(statementID).kind)
        else {
            return
        }

        let rawHeaderTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
            token.kind != .symbol(.semicolon)
        }
        let annotations = annotationsFromTokens(rawHeaderTokens, interner: interner)
        guard let accessorStart = inlineAccessorStartIndex(in: rawHeaderTokens, bodyIsSiblingBlock: true) else { return }
        let headerTokens = Array(rawHeaderTokens[accessorStart...])
        guard let firstToken = headerTokens.first else {
            return
        }

        let kind: PropertyAccessorKind
        switch firstToken.kind {
        case .softKeyword(.get): kind = .getter
        case .softKeyword(.set): kind = .setter
        default: return
        }

        let parameterName: InternedString? = kind == .setter
            ? setterParameterName(from: headerTokens, interner: interner)
            : nil

        let body = accessorBody(
            statementID: statementID,
            headerTokens: headerTokens,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let accessor = PropertyAccessorDecl(
            range: arena.node(statementID).range,
            kind: kind,
            annotations: annotations,
            parameterName: parameterName,
            body: body
        )
        switch kind {
        case .getter: if getter == nil { getter = accessor }
        case .setter: if setter == nil { setter = accessor }
        }
    }

    func setterParameterName(
        from headerTokens: [Token],
        interner: StringInterner
    ) -> InternedString? {
        guard let openParenIndex = headerTokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        for token in headerTokens[(openParenIndex + 1)...] {
            if token.kind == .symbol(.rParen) {
                break
            }
            if let name = internedIdentifier(from: token, interner: interner),
               TypeRefParserCore.isDeclarationNameToken(token.kind)
            {
                return name
            }
        }
        return nil
    }

    /// Splits a property node's direct children into one segment per inline
    /// accessor (`get(...)` / `set(...)` not preceded by `.`), pairing each
    /// header with the sibling block(s) that follow it before the next one.
    private func siblingBlockAccessors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        enum Item {
            case token(Token)
            case block(NodeID)
        }
        var items: [Item] = []
        for child in arena.children(of: nodeID) {
            switch child {
            case let .token(tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    items.append(.token(token))
                }
            case let .node(childID):
                if arena.node(childID).kind == .block {
                    items.append(.block(childID))
                }
            }
        }

        func isAccessorStart(_ index: Int) -> Bool {
            guard case let .token(token) = items[index] else { return false }
            switch token.kind {
            case .softKeyword(.get), .softKeyword(.set): break
            default: return false
            }
            guard index + 1 < items.count,
                  case let .token(next) = items[index + 1],
                  next.kind == .symbol(.lParen)
            else {
                return false
            }
            if index > 0, case let .token(previous) = items[index - 1] {
                switch previous.kind {
                case .symbol(.dot), .symbol(.questionDot): return false
                default: break
                }
            }
            return true
        }

        let starts = items.indices.filter(isAccessorStart)
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        for (position, start) in starts.enumerated() {
            let end = position + 1 < starts.count ? starts[position + 1] : items.count
            var headerTokens: [Token] = []
            var accessorTokens: [Token] = []
            var firstBlock: NodeID?
            for item in items[start ..< end] {
                switch item {
                case let .token(token):
                    accessorTokens.append(token)
                    if token.kind != .symbol(.semicolon) { headerTokens.append(token) }
                case let .block(blockID):
                    accessorTokens.append(contentsOf: collectTokens(from: blockID, in: arena))
                    if firstBlock == nil { firstBlock = blockID }
                }
            }
            guard case let .softKeyword(keyword) = headerTokens[0].kind else { continue }
            let kind: PropertyAccessorKind = keyword == .get ? .getter : .setter
            let accessor = PropertyAccessorDecl(
                range: arena.node(nodeID).range,
                kind: kind,
                annotations: accessorAnnotations(
                    from: items[..<start].compactMap { item in
                        if case let .token(token) = item { return token }
                        return nil
                    }, interner: interner
                ),
                parameterName: kind == .setter
                    ? setterParameterName(from: headerTokens, interner: interner)
                    : nil,
                body: accessorBody(
                    headerTokens: headerTokens, accessorTokens: accessorTokens, firstBlock: firstBlock,
                    in: arena, interner: interner, astArena: astArena
                )
            )
            switch kind {
            case .getter: if getter == nil { getter = accessor }
            case .setter: if setter == nil { setter = accessor }
            }
        }
        return (getter, setter)
    }

    func accessorBody(
        statementID: NodeID,
        headerTokens: [Token],
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        let firstBlock = arena.children(of: statementID).compactMap { child -> NodeID? in
            guard case let .node(nodeID) = child,
                  arena.node(nodeID).kind == .block else { return nil }
            return nodeID
        }.first
        return accessorBody(
            headerTokens: headerTokens, accessorTokens: collectTokens(from: statementID, in: arena),
            firstBlock: firstBlock,
            in: arena, interner: interner, astArena: astArena
        )
    }

    private func accessorBody(
        headerTokens: [Token],
        accessorTokens: [Token],
        firstBlock: NodeID?,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        // Expression accessors can contain several trailing lambdas, separated
        // by operators or calls. Keep every block in its original token order,
        // including semicolons separating statements inside lambda bodies.
        if headerTokens.contains(where: { $0.kind == .symbol(.assign) }),
           let assignIndex = accessorTokens.firstIndex(where: { $0.kind == .symbol(.assign) })
        {
            let exprTokens = Array(accessorTokens[(assignIndex + 1)...])
            if let exprID = ExpressionParser(
                tokens: ArraySlice(exprTokens), interner: interner,
                astArena: astArena, diagnostics: diagnostics
            ).parse(), let range = astArena.exprRange(exprID) {
                return .expr(exprID, range)
            }
            return .unit
        }

        if let nestedBlockID = firstBlock {
            let exprs = blockExpressions(
                from: nestedBlockID,
                in: arena,
                interner: interner,
                astArena: astArena
            )
            return .block(exprs, arena.node(nestedBlockID).range)
        }

        return .unit
    }

    // MARK: - Explicit Backing Field (Kotlin 2.0)

    /// Extracts an explicit backing field declaration from a property node.
    /// Looks for a `.propertyAccessor` child whose tokens start with the
    /// `field` soft keyword, followed by `= expr` or `: Type = expr`.
    func declarationExplicitBackingField(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExplicitBackingField? {
        // Search for a propertyAccessor child that starts with `field`.
        for child in arena.children(of: nodeID) {
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .propertyAccessor
            else { continue }
            let tokens = collectTokens(from: childID, in: arena)
            guard let firstToken = tokens.first,
                  case .softKeyword(.field) = firstToken.kind
            else { continue }
            return parseExplicitBackingFieldTokens(tokens, interner: interner, astArena: astArena)
        }

        // Also check inside a block child (e.g. `val x: T { field = ... get() = ... }`).
        if let blockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else { return nil }
            return childID
        }).first {
            for child in arena.children(of: blockID) {
                guard case let .node(stmtID) = child,
                      isStatementLikeKind(arena.node(stmtID).kind)
                else { continue }
                let tokens = collectDirectTokens(from: stmtID, in: arena)
                guard let firstToken = tokens.first,
                      case .softKeyword(.field) = firstToken.kind
                else { continue }
                let allTokens = collectTokens(from: stmtID, in: arena)
                return parseExplicitBackingFieldTokens(allTokens, interner: interner, astArena: astArena)
            }
        }

        return nil
    }

    /// Parse `field = expr` or `field : Type = expr` from a token sequence.
    private func parseExplicitBackingFieldTokens(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExplicitBackingField? {
        // tokens[0] is `field`
        guard tokens.count >= 2 else { return nil }
        var index = 1

        // Check for optional type annotation: `field: Type = expr`
        var fieldType: TypeRefID?
        if tokens[index].kind == .symbol(.colon) {
            index += 1
            // Collect type tokens until `=`
            var typeTokens: [Token] = []
            var depth = BracketDepth()
            while index < tokens.count {
                let token = tokens[index]
                if token.kind == .symbol(.assign), depth.isAtTopLevel {
                    break
                }
                depth.track(token.kind)
                typeTokens.append(token)
                index += 1
            }
            if !typeTokens.isEmpty {
                fieldType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
            }
        }

        // Expect `=`
        guard index < tokens.count, tokens[index].kind == .symbol(.assign) else {
            return nil
        }
        index += 1

        // Parse initializer expression
        let exprTokens = tokens[index...].filter { $0.kind != .symbol(.semicolon) }
        guard !exprTokens.isEmpty else { return nil }
        let parser = ExpressionParser(
            tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        guard let initExpr = parser.parse() else { return nil }

        return ExplicitBackingField(type: fieldType, initializer: initExpr)
    }
}
