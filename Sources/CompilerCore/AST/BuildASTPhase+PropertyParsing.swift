
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
            // A block after an initializer or delegate belongs to that expression.
            // Its object members must not become accessors of the outer property.
            let hasInitializerOrDelegate = directTokens.contains {
                $0.kind == .symbol(.assign) || $0.kind == .softKeyword(.by)
            }
            if !foundSiblingBlockAccessor, !hasInitializerOrDelegate {
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
                        interner: interner, astArena: astArena,
                        isAccessorNode: true
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
            // Kotlin's default setter may be written as a bare `set` after an
            // explicitly typed property. It has neither a parameter list nor
            // a body, but still starts an accessor and must not become part of
            // the property's type tokens.
            if case .softKeyword(.set) = token.kind,
               isBareDefaultSetter(in: tokens[...], at: index)
            {
                return index
            }
            // Custom accessors require a parameter list.
            guard index + 1 < tokens.count,
                  tokens[index + 1].kind == .symbol(.lParen)
            else {
                continue
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

    private func isBareDefaultSetter(in tokens: ArraySlice<Token>, at index: Int) -> Bool {
        guard tokens.indices.contains(index),
              case .softKeyword(.set) = tokens[index].kind
        else {
            return false
        }

        let afterSetter = tokens.index(after: index)
        if afterSetter < tokens.endIndex {
            guard tokens[afterSetter].kind == .symbol(.semicolon),
                  tokens.index(after: afterSetter) == tokens.endIndex
            else {
                return false
            }
        }

        guard let propertyIndex = tokens[..<index].lastIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return false
        }

        var sawTypeSeparator = false
        var sawTypeToken = false
        var depth = BracketDepth()
        for token in tokens[(propertyIndex + 1) ..< index] {
            if depth.isAtTopLevel {
                switch token.kind {
                case .symbol(.colon):
                    sawTypeSeparator = true
                case .symbol(.assign), .softKeyword(.by):
                    return false
                default:
                    break
                }
                if sawTypeSeparator {
                    switch token.kind {
                    case .keyword(.public), .keyword(.private), .keyword(.internal),
                         .keyword(.protected), .keyword(.inline):
                        break
                    default:
                        sawTypeToken = true
                    }
                }
            }
            depth.track(token.kind)
        }
        return sawTypeSeparator && sawTypeToken
    }

    private func accessorVisibility(in tokensBeforeAccessor: [Token]) -> Visibility? {
        let propertyStart = tokensBeforeAccessor.lastIndex { token in
            token.kind == .keyword(.val) || token.kind == .keyword(.var)
        }
        let previousAccessor = tokensBeforeAccessor.lastIndex { token in
            token.kind == .softKeyword(.get) || token.kind == .softKeyword(.set)
        }
        let startIndex = max(propertyStart ?? -1, previousAccessor ?? -1) + 1

        for token in tokensBeforeAccessor.dropFirst(startIndex).reversed() {
            guard case let .keyword(keyword) = token.kind else { continue }
            switch keyword {
            case .public: return .public
            case .private: return .private
            case .internal: return .internal
            case .protected: return .protected
            default: continue
            }
        }
        return nil
    }

    private func accessorIsInline(in tokensBeforeAccessor: [Token]) -> Bool {
        let start = tokensBeforeAccessor.lastIndex {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
                || $0.kind == .softKeyword(.get) || $0.kind == .softKeyword(.set)
        }.map { $0 + 1 } ?? 0
        var depth = BracketDepth()
        for index in start ..< tokensBeforeAccessor.count {
            let token = tokensBeforeAccessor[index]
            let isNameToken = index > start
                && (tokensBeforeAccessor[index - 1].kind == .symbol(.at)
                    || tokensBeforeAccessor[index - 1].kind == .symbol(.dot)
                    || tokensBeforeAccessor[index - 1].kind == .symbol(.colon)
                    || tokensBeforeAccessor[index - 1].kind == .symbol(.arrow)
                    || tokensBeforeAccessor[index - 1].kind == .symbol(.assign))
            if depth.isAtTopLevel, token.kind == .keyword(.inline), !isNameToken { return true }
            depth.track(token.kind)
        }
        return false
    }

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

    private func parseInlineAccessors(
        from allTokens: [Token],
        nodeRange: SourceRange,
        interner: StringInterner,
        astArena: ASTArena,
        isAccessorNode: Bool = false
    ) -> (getter: PropertyAccessorDecl?, setter: PropertyAccessorDecl?) {
        var getter: PropertyAccessorDecl?
        var setter: PropertyAccessorDecl?
        var remaining = allTokens[...]

        while let startIdx = topLevelAccessorKeywordIndex(in: remaining) {
            let tokensBeforeAccessor = Array(remaining[..<startIdx])
            let annotations = accessorAnnotations(from: tokensBeforeAccessor, interner: interner)
            let token = remaining[startIdx]
            let kind: PropertyAccessorKind
            switch token.kind {
            case .softKeyword(.get): kind = .getter
            case .softKeyword(.set): kind = .setter
            default:
                remaining = remaining[(startIdx + 1)...]
                continue
            }

            // Dedicated CST accessor nodes can contain a bodyless getter or
            // setter. Preserve their annotations even without a parameter list.
            // Flat property tokens still need the default-setter shape check
            // so an ordinary name in a type or expression is not an accessor.
            let hasParameterList = startIdx + 1 < remaining.endIndex
                && remaining[startIdx + 1].kind == .symbol(.lParen)
            let explicitAccessorVisibility = accessorVisibility(in: tokensBeforeAccessor)
            if !hasParameterList,
               isAccessorNode || (kind == .setter
                   && (explicitAccessorVisibility != nil || isBareDefaultSetter(in: remaining, at: startIdx)))
            {
                let accessor = PropertyAccessorDecl(
                    range: isAccessorNode ? nodeRange : token.range,
                    kind: kind,
                    annotations: annotations,
                    visibility: explicitAccessorVisibility
                )
                switch kind {
                case .getter: if getter == nil { getter = accessor }
                case .setter: if setter == nil { setter = accessor }
                }
                remaining = remaining[(startIdx + 1)...]
                continue
            }
            guard hasParameterList else {
                remaining = remaining[(startIdx + 1)...]
                continue
            }
            let accessorTokens = Array(remaining[startIdx...])

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

            var afterParen = closeParenIdx + 1
            if afterParen < remaining.endIndex,
               remaining[afterParen].kind == .symbol(.colon)
            {
                let colonToken = remaining[afterParen]
                afterParen += 1
                var sawTypeToken = false
                var typeDepth = BracketDepth()
                while afterParen < remaining.endIndex {
                    if typeDepth.isAtTopLevel {
                        switch remaining[afterParen].kind {
                        case .symbol(.assign), .symbol(.lBrace):
                            break
                        default:
                            typeDepth.track(remaining[afterParen].kind)
                            sawTypeToken = true
                            afterParen += 1
                            continue
                        }
                        break
                    }
                    typeDepth.track(remaining[afterParen].kind)
                    sawTypeToken = true
                    afterParen += 1
                }
                if !sawTypeToken {
                    let following = afterParen < remaining.endIndex ? remaining[afterParen] : nil
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0020",
                        "Expected type after ':'.",
                        range: following?.range ?? colonToken.range
                    )
                }
            }
            let body: FunctionBody
            if afterParen < remaining.endIndex,
               remaining[afterParen].kind == .symbol(.assign)
            {
                // A `get`/`set` soft keyword only opens the next accessor when it
                // starts an accessor header: at top level, followed by `(`, and
                // not preceded by a navigation operator. Member-call tokens like
                // `this.get()` or a `get(` nested inside call arguments or a
                // lambda are part of the body expression, not a boundary.
                let exprStart = afterParen + 1
                var exprEnd = remaining.endIndex
                var bodyDepth = BracketDepth()
                let bodyTokens = Array(remaining)
                let exprStartOffset = exprStart - remaining.startIndex
                for bodyIndex in exprStartOffset ..< bodyTokens.endIndex {
                    let token = bodyTokens[bodyIndex]
                    switch token.kind {
                    case .softKeyword(.get), .softKeyword(.set):
                        let precededByNavigation = bodyIndex > exprStartOffset
                            && (bodyTokens[bodyIndex - 1].kind == .symbol(.dot)
                                || bodyTokens[bodyIndex - 1].kind == .symbol(.questionDot)
                                || bodyTokens[bodyIndex - 1].kind == .symbol(.doubleColon))
                        if bodyDepth.isAtTopLevel,
                           !precededByNavigation,
                           isAccessorHeader(in: bodyTokens, at: bodyIndex)
                        {
                            exprEnd = remaining.startIndex + bodyIndex
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

            let accessorEndIndex = remaining.startIndex
            let lastConsumed = accessorEndIndex > startIdx ? allTokens[accessorEndIndex - 1] : token
            let accessorRange = SourceRange(start: token.range.start, end: lastConsumed.range.end)
            let accessor = PropertyAccessorDecl(
                range: accessorRange,
                kind: kind,
                annotations: annotations,
                visibility: accessorVisibility(in: tokensBeforeAccessor),
                isInline: accessorIsInline(in: tokensBeforeAccessor),
                parameterName: parameterName,
                returnType: accessorReturnType(
                    from: accessorTokens,
                    kind: kind,
                    interner: interner,
                    astArena: astArena
                ),
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

    private func isAccessorHeader(in tokens: [Token], at start: Int) -> Bool {
        guard start + 1 < tokens.endIndex,
              tokens[start + 1].kind == .symbol(.lParen)
        else {
            return false
        }

        let isGetter: Bool
        switch tokens[start].kind {
        case .softKeyword(.get): isGetter = true
        case .softKeyword(.set): isGetter = false
        default: return false
        }

        let afterClose = skipBalancedBracket(
            in: tokens,
            from: start + 1,
            open: .symbol(.lParen),
            close: .symbol(.rParen)
        )
        guard afterClose > start + 2 else { return false }

        // A getter header has no parameters. Calls such as `get(0)` inside an
        // expression body therefore cannot begin another accessor.
        if isGetter, afterClose != start + 3 { return false }

        var bodyStart = afterClose
        if bodyStart < tokens.endIndex,
           tokens[bodyStart].kind == .symbol(.colon)
        {
            bodyStart += 1
            var typeDepth = BracketDepth()
            while bodyStart < tokens.endIndex {
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

        guard bodyStart < tokens.endIndex else { return false }
        switch tokens[bodyStart].kind {
        case .symbol(.assign), .symbol(.lBrace):
            return true
        default:
            return false
        }
    }

    func accessorReturnType(
        from tokens: [Token],
        kind: PropertyAccessorKind,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard kind == .getter,
              let openParenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) })
        else {
            return nil
        }
        let afterParen = skipBalancedBracket(
            in: tokens,
            from: openParenIndex,
            open: .symbol(.lParen),
            close: .symbol(.rParen)
        )
        guard afterParen < tokens.endIndex,
              tokens[afterParen].kind == .symbol(.colon)
        else {
            return nil
        }

        let typeStart = afterParen + 1
        var typeEnd = typeStart
        var depth = BracketDepth()
        while typeEnd < tokens.endIndex {
            let token = tokens[typeEnd]
            if depth.isAtTopLevel {
                switch token.kind {
                case .symbol(.assign), .symbol(.lBrace), .symbol(.semicolon),
                     .softKeyword(.get), .softKeyword(.set):
                    return parseTypeRef(
                        from: Array(tokens[typeStart ..< typeEnd]),
                        interner: interner,
                        astArena: astArena
                    )
                default:
                    break
                }
            }
            depth.track(token.kind)
            typeEnd += 1
        }
        return parseTypeRef(
            from: Array(tokens[typeStart ..< typeEnd]),
            interner: interner,
            astArena: astArena
        )
    }

    private func topLevelAccessorKeywordIndex(in tokens: ArraySlice<Token>) -> Int? {
        var depth = BracketDepth()
        for index in tokens.indices {
            let token = tokens[index]
            if depth.isBracketBraceParenTopLevel,
               token.kind == .softKeyword(.get) || token.kind == .softKeyword(.set) {
                if index > tokens.startIndex {
                    switch tokens[index - 1].kind {
                    case .symbol(.dot), .symbol(.questionDot):
                        continue
                    default:
                        break
                    }
                }
                return index
            }
            depth.track(token.kind)
        }
        return nil
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
        guard let accessorStart = inlineAccessorStartIndex(in: rawHeaderTokens, bodyIsSiblingBlock: true) else { return }
        let annotations = annotationsFromTokens(Array(rawHeaderTokens[..<accessorStart]), interner: interner)
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
            visibility: accessorVisibility(in: Array(rawHeaderTokens[..<accessorStart])),
            isInline: accessorIsInline(in: Array(rawHeaderTokens[..<accessorStart])),
            parameterName: parameterName,
            returnType: accessorReturnType(
                from: headerTokens,
                kind: kind,
                interner: interner,
                astArena: astArena
            ),
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
        guard let accessorStart = inlineAccessorStartIndex(in: rawHeaderTokens, bodyIsSiblingBlock: true) else { return }
        let annotations = annotationsFromTokens(Array(rawHeaderTokens[..<accessorStart]), interner: interner)
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
            visibility: accessorVisibility(in: Array(rawHeaderTokens[..<accessorStart])),
            isInline: accessorIsInline(in: Array(rawHeaderTokens[..<accessorStart])),
            parameterName: parameterName,
            returnType: accessorReturnType(
                from: headerTokens,
                kind: kind,
                interner: interner,
                astArena: astArena
            ),
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
        var depth = 0
        var nameToken: Token?
        var colonIndex: Int?
        var sawTokenAfterColon = false
        for index in (openParenIndex + 1) ..< headerTokens.count {
            let token = headerTokens[index]
            if token.kind == .symbol(.rParen), depth == 0 {
                break
            }
            switch token.kind {
            case .symbol(.lParen), .symbol(.lBracket):
                depth += 1
            case .symbol(.rParen), .symbol(.rBracket):
                depth -= 1
            default:
                break
            }
            if depth == 0, token.kind == .symbol(.colon), colonIndex == nil {
                colonIndex = index
                continue
            }
            if colonIndex != nil {
                sawTokenAfterColon = true
            } else if nameToken == nil,
                      internedIdentifier(from: token, interner: interner) != nil,
                      TypeRefParserCore.isDeclarationNameToken(token.kind)
            {
                nameToken = token
            }
        }
        if let colonIndex, !sawTokenAfterColon {
            let following = colonIndex + 1 < headerTokens.count ? headerTokens[colonIndex + 1] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? headerTokens[colonIndex].range
            )
        }
        guard let nameToken else {
            return nil
        }
        return internedIdentifier(from: nameToken, interner: interner)
    }

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
            let prefixTokens = items[..<start].compactMap { item -> Token? in
                if case let .token(token) = item { return token }
                return nil
            }
            var accessorRange = arena.node(nodeID).range
            if case let .token(startToken) = items[start], let lastToken = accessorTokens.last {
                accessorRange = SourceRange(start: startToken.range.start, end: lastToken.range.end)
            }
            let accessor = PropertyAccessorDecl(
                range: accessorRange,
                kind: kind,
                annotations: accessorAnnotations(
                    from: prefixTokens, interner: interner
                ),
                visibility: accessorVisibility(in: prefixTokens),
                isInline: accessorIsInline(in: prefixTokens),
                parameterName: kind == .setter
                    ? setterParameterName(from: headerTokens, interner: interner)
                    : nil,
                returnType: accessorReturnType(
                    from: headerTokens,
                    kind: kind,
                    interner: interner,
                    astArena: astArena
                ),
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

    /// `get(): = x` / `set(v): { }` — the `:` after an accessor's parameter list
    /// introduces a required return type, so an empty one is a parse error.
    private func reportEmptyAccessorReturnType(in headerTokens: [Token]) {
        var index = 1
        var parenDepth = 0
        while index < headerTokens.count {
            let token = headerTokens[index]
            if token.kind == .symbol(.lParen) {
                parenDepth += 1
            } else if token.kind == .symbol(.rParen) {
                parenDepth -= 1
                if parenDepth == 0 {
                    index += 1
                    break
                }
            }
            index += 1
        }
        guard index < headerTokens.count, headerTokens[index].kind == .symbol(.colon) else {
            return
        }
        let colonToken = headerTokens[index]
        var sawTypeToken = false
        var typeDepth = BracketDepth()
        var cursor = index + 1
        while cursor < headerTokens.count {
            let token = headerTokens[cursor]
            if typeDepth.isAtTopLevel, token.kind == .symbol(.assign) {
                break
            }
            typeDepth.track(token.kind)
            sawTypeToken = true
            cursor += 1
        }
        if !sawTypeToken {
            let following = cursor < headerTokens.count ? headerTokens[cursor] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? colonToken.range
            )
        }
    }

    private func accessorBody(
        headerTokens: [Token],
        accessorTokens: [Token],
        firstBlock: NodeID?,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        reportEmptyAccessorReturnType(in: headerTokens)
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

    func declarationExplicitBackingField(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExplicitBackingField? {
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

    private func parseExplicitBackingFieldTokens(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExplicitBackingField? {
        guard tokens.count >= 2 else { return nil }
        var index = 1

        var fieldType: TypeRefID?
        if tokens[index].kind == .symbol(.colon) {
            let colonToken = tokens[index]
            index += 1
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
            fieldType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
            if fieldType == nil {
                let following = index < tokens.count ? tokens[index] : nil
                diagnostics?.error(
                    "KSWIFTK-PARSE-0020",
                    "Expected type after ':'.",
                    range: following?.range ?? colonToken.range
                )
            }
        }

        guard index < tokens.count, tokens[index].kind == .symbol(.assign) else {
            let trailingTokens = tokens.dropFirst(index)
            guard fieldType != nil,
                  trailingTokens.allSatisfy({ $0.kind == .symbol(.semicolon) })
            else {
                return nil
            }
            return ExplicitBackingField(type: fieldType)
        }
        index += 1

        let exprTokens = tokens[index...].filter { $0.kind != .symbol(.semicolon) }
        guard !exprTokens.isEmpty else { return nil }
        let parser = ExpressionParser(
            tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        guard let initExpr = parser.parse() else { return nil }

        return ExplicitBackingField(type: fieldType, initializer: initExpr)
    }
}
