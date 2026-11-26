
extension BuildASTPhase {
    func splitDefaultValue(_ tokens: [Token]) -> (withoutDefault: [Token], defaultTokens: [Token]?) {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
                let defaultStart = tokens.index(after: index)
                let trailing = defaultStart < tokens.endIndex ? Array(tokens[defaultStart...]) : []
                return (Array(tokens[..<index]), trailing)
            }
            depth.track(token.kind)
        }
        return (tokens, nil)
    }

    func declarationFunctionName(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let paramsOpenIndex = functionParameterOpenParenIndex(in: tokens) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }
        guard let funIndex = functionKeywordIndex(in: tokens), paramsOpenIndex > funIndex else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        for index in stride(from: paramsOpenIndex - 1, through: funIndex + 1, by: -1) {
            let token = tokens[index]
            if !TypeRefParserCore.isTypeLikeNameToken(token.kind) {
                continue
            }
            if let name = internedIdentifier(from: token, interner: interner) {
                return name
            }
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        return declarationReceiverType(from: tokens, interner: interner, astArena: astArena)
    }

    func declarationReceiverType(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard let paramsOpenIndex = functionParameterOpenParenIndex(in: tokens),
              paramsOpenIndex > 0
        else {
            return nil
        }

        var nameIndex: Int?
        for index in stride(from: paramsOpenIndex - 1, through: 0, by: -1)
            where TypeRefParserCore.isDeclarationNameToken(tokens[index].kind) {
            nameIndex = index
            break
        }
        guard let nameIndex else {
            return nil
        }

        var receiverSeparatorIndex: Int?
        var receiverSeparatorToken: Token?
        var depth = BracketDepth()
        for index in 0 ..< nameIndex {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0,
               token.kind == .symbol(.dot) || token.kind == .symbol(.questionDot)
            {
                receiverSeparatorIndex = index
                receiverSeparatorToken = token
            }
        }
        guard let receiverSeparatorIndex else {
            return nil
        }

        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return nil
        }

        let receiverStart = skipBalancedBracket(
            in: tokens, from: funIndex + 1,
            open: .symbol(.lessThan), close: .symbol(.greaterThan)
        )

        var receiverTypeStart = receiverStart
        while receiverTypeStart < tokens.count,
              let annotation = AnnotationParsingSupport.parseAnnotation(
                  from: tokens,
                  start: receiverTypeStart,
                  interner: interner,
                  allowUseSiteTarget: true
              ),
              annotation.annotation.useSiteTarget?.lowercased() == "receiver"
        {
            receiverTypeStart = annotation.nextIndex
        }

        if receiverTypeStart >= receiverSeparatorIndex {
            return nil
        }

        var receiverTokens = Array(tokens[receiverTypeStart ..< receiverSeparatorIndex])
        if receiverSeparatorToken?.kind == .symbol(.questionDot),
           let separatorRange = receiverSeparatorToken?.range
        {
            receiverTokens.append(Token(kind: .symbol(.question), range: separatorRange))
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationReceiverAnnotations(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [AnnotationNode] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let funIndex = tokens.firstIndex(where: { $0.kind == .keyword(.fun) }) else {
            return []
        }

        var index = skipBalancedBracket(
            in: tokens,
            from: funIndex + 1,
            open: .symbol(.lessThan),
            close: .symbol(.greaterThan)
        )
        var annotations: [AnnotationNode] = []
        while index < tokens.count,
              let parsed = AnnotationParsingSupport.parseAnnotation(
                  from: tokens,
                  start: index,
                  interner: interner,
                  allowUseSiteTarget: true
              ),
              parsed.annotation.useSiteTarget?.lowercased() == "receiver"
        {
            annotations.append(parsed.annotation)
            index = parsed.nextIndex
        }
        return annotations
    }

    func declarationContextReceivers(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ContextReceiverDecl] {
        let allTokens = collectTokens(from: nodeID, in: arena)
        // Context clauses are declaration modifiers, so they precede `fun`, `val`, or `var`.
        // Restricting the scan keeps a `context(...)` function type in the parameter
        // list — or a function literally named `context` — from being mistaken for
        // a declaration-level context clause.
        let declarationIndex = allTokens.firstIndex(where: { token in
            token.kind == .keyword(.fun) || token.kind == .keyword(.val) || token.kind == .keyword(.var)
        })
        let tokens = if let declarationIndex {
            Array(allTokens[..<declarationIndex])
        } else {
            allTokens
        }
        return parseContextReceivers(from: tokens, interner: interner, astArena: astArena)
    }

    func parseContextReceivers(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ContextReceiverDecl] {
        var contextIndex: Int?
        var prefixIndex = 0
        while prefixIndex < tokens.count {
            let kind = tokens[prefixIndex].kind
            if kind == .symbol(.at) {
                guard let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: tokens,
                    start: prefixIndex,
                    interner: interner,
                    allowUseSiteTarget: true
                ) else {
                    return []
                }
                prefixIndex = parsed.nextIndex
                continue
            }
            if case let .keyword(keyword) = kind,
               KotlinParser.isDeclarationModifierKeyword(keyword)
            {
                prefixIndex += 1
                continue
            }
            if kind == .softKeyword(.context) {
                contextIndex = prefixIndex
            }
            break
        }
        guard let contextIndex,
              contextIndex + 1 < tokens.count,
              tokens[contextIndex + 1].kind == .symbol(.lParen)
        else {
            return []
        }
        var index = contextIndex + 2
        var depth = 1
        var current: [Token] = []
        var items: [ContextReceiverDecl] = []
        var sawComma = false
        func appendCurrentItem() {
            guard let item = parseContextReceiverItem(from: current, interner: interner, astArena: astArena) else {
                return
            }
            items.append(ContextReceiverDecl(
                name: item.name,
                type: item.ref,
                isContextParameter: item.isContextParameter,
                isCrossinline: item.isCrossinline,
                isNoinline: item.isNoinline
            ))
        }
        while index < tokens.count, depth > 0 {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                depth += 1
                current.append(token)
            } else if token.kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    if !current.isEmpty {
                        appendCurrentItem()
                    } else if !sawComma {
                        diagnostics?.error(
                            "KSWIFTK-PARSE-0001",
                            "Empty context parameter list.",
                            range: token.range
                        )
                    }
                    break
                }
                current.append(token)
            } else if token.kind == .symbol(.comma), depth == 1 {
                sawComma = true
                if current.isEmpty {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0001",
                        "Expecting a parameter declaration.",
                        range: token.range
                    )
                } else {
                    appendCurrentItem()
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(token)
            }
            index += 1
        }
        return items
    }

    private func parseContextReceiverItem(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> (
        name: InternedString?,
        ref: TypeRefID,
        isContextParameter: Bool,
        isCrossinline: Bool,
        isNoinline: Bool
    )? {
        var name: InternedString?
        var typeTokens = tokens
        var isContextParameter = false
        var isCrossinline = false
        var isNoinline = false
        while let first = typeTokens.first {
            if first.kind == .symbol(.at),
               let parsed = AnnotationParsingSupport.parseAnnotation(
                   from: typeTokens,
                   start: 0,
                   interner: interner,
                   allowUseSiteTarget: false
               )
            {
                typeTokens.removeFirst(parsed.nextIndex)
            } else if first.kind == .keyword(.crossinline) {
                isCrossinline = true
                typeTokens.removeFirst()
            } else if first.kind == .keyword(.noinline) {
                isNoinline = true
                typeTokens.removeFirst()
            } else {
                break
            }
        }
        let hasInlineParameterModifier = isCrossinline || isNoinline
        let nameColonRange = typeTokens.count > 1 && typeTokens[1].kind == .symbol(.colon)
            ? typeTokens[1].range
            : nil
        if typeTokens.count > 2,
           nameColonRange != nil
        {
            isContextParameter = true
            switch typeTokens[0].kind {
            case let .identifier(ident):
                if interner.resolve(ident) != "_" {
                    name = ident
                }
                typeTokens = Array(typeTokens.dropFirst(2))
            case let .backtickedIdentifier(ident):
                name = ident
                typeTokens = Array(typeTokens.dropFirst(2))
            case .softKeyword(.context):
                name = interner.intern("context")
                typeTokens = Array(typeTokens.dropFirst(2))
            default:
                break
            }
        }
        if hasInlineParameterModifier, !isContextParameter {
            diagnostics?.error(
                "KSWIFTK-PARSE-0002",
                "Expected a context parameter name after inline parameter modifier.",
                range: tokens.first?.range
            )
            return nil
        }
        guard let ref = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            if let nameColonRange {
                let following = isContextParameter ? typeTokens.first : nil
                diagnostics?.error(
                    "KSWIFTK-PARSE-0020",
                    "Expected type after ':'.",
                    range: following?.range ?? nameColonRange
                )
            } else if !isContextParameter {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0030",
                    "context parameters must be named. Use '_' to declare an anonymous context parameter.",
                    range: typeTokens.first?.range ?? tokens.first?.range
                )
            }
            return nil
        }
        if !isContextParameter {
            diagnostics?.error(
                "KSWIFTK-PARSE-0030",
                "context parameters must be named. Use '_' to declare an anonymous context parameter.",
                range: typeTokens.first?.range ?? tokens.first?.range
            )
        }
        return (name, ref, isContextParameter, isCrossinline, isNoinline)
    }

    func declarationReturnType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let closeParenIndex = firstFunctionParameterCloseParen(in: tokens) else {
            return nil
        }

        var colonIndex: Int?
        var index = closeParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                return nil
            }
            if case .softKeyword(.where) = token.kind {
                return nil
            }
            if token.kind == .symbol(.colon) {
                colonIndex = index
                index += 1
                break
            }
            index += 1
        }

        guard let colonIndex else {
            return nil
        }

        var typeTokens: [Token] = []
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.angle == 0 {
                if token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                    || token.kind == .symbol(.semicolon)
                {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }

        guard let returnType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            let following = colonIndex + 1 < tokens.count ? tokens[colonIndex + 1] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? tokens[colonIndex].range
            )
            return nil
        }
        return returnType
    }

    func declarationPropertyReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena, interner: interner)

        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return nil
        }

        guard let separatorIndex = declarationPropertyReceiverSeparatorIndex(
            in: tokens,
            after: valVarIndex
        ) else {
            return nil
        }

        var receiverTokens = Array(tokens[(valVarIndex + 1) ..< separatorIndex])
        guard !receiverTokens.isEmpty else {
            return nil
        }
        if tokens[separatorIndex].kind == .symbol(.questionDot) {
            receiverTokens.append(Token(kind: .symbol(.question), range: tokens[separatorIndex].range))
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationPropertyNameAfterDot(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = propertyHeadTokens(from: nodeID, in: arena, interner: interner)

        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        guard let separatorIndex = declarationPropertyReceiverSeparatorIndex(
            in: tokens,
            after: valVarIndex
        ), separatorIndex + 1 < tokens.count else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        let nameToken = tokens[separatorIndex + 1]
        if let name = internedIdentifier(from: nameToken, interner: interner) {
            return name
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    private func declarationPropertyReceiverSeparatorIndex(
        in tokens: [Token],
        after valVarIndex: Int
    ) -> Int? {
        var depth = BracketDepth()
        var lastSeparatorIndex: Int?
        for index in (valVarIndex + 1) ..< tokens.count {
            let token = tokens[index]
            depth.track(token.kind)
            guard depth.angle == 0 else { continue }
            if token.kind == .symbol(.dot) || token.kind == .symbol(.questionDot) {
                lastSeparatorIndex = index
            } else if token.kind == .symbol(.colon)
                || token.kind == .symbol(.assign)
                || token.kind == .symbol(.lBrace)
                || token.kind == .softKeyword(.by)
            {
                break
            }
        }
        return lastSeparatorIndex
    }

    func declarationPropertyType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena, interner: interner)
        // A use-site annotation before the declaration can contain a colon
        // (`@get:JvmSynthetic`). It must not become the property's type separator.
        guard let declarationIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return nil
        }
        var sawName = false
        var colonIndex: Int?
        for (index, token) in tokens.enumerated().dropFirst(declarationIndex + 1) {
            if !sawName {
                switch token.kind {
                case .keyword(.val), .keyword(.var):
                    continue
                default:
                    if TypeRefParserCore.isDeclarationNameToken(token.kind) {
                        sawName = true
                    }
                    continue
                }
            }

            if token.kind == .symbol(.colon) {
                colonIndex = index
                break
            }
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                return nil
            }
            if case .softKeyword(.by) = token.kind {
                return nil
            }
        }

        guard let colonIndex else {
            return nil
        }

        let typeTokens = collectPropertyTypeTokens(afterColonIndex: colonIndex, tokens: tokens)
        guard let typeRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            let following = colonIndex + 1 < tokens.count ? tokens[colonIndex + 1] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? tokens[colonIndex].range
            )
            return nil
        }
        return typeRef
    }

    private func isSiblingBlockAccessorHeader(
        at index: Int,
        in children: [SyntaxChild],
        arena: SyntaxArena,
        previous: Token?
    ) -> Bool {
        if let previous {
            switch previous.kind {
            case .symbol(.dot), .symbol(.questionDot): return false
            default: break
            }
        }
        var following: [Token] = []
        for child in children[(index + 1)...] {
            switch child {
            case let .token(tokenID):
                guard let token = resolveToken(tokenID, in: arena) else { continue }
                following.append(token)
            case let .node(childID):
                guard arena.node(childID).kind == .block,
                      following.first?.kind == .symbol(.lParen)
                else {
                    return false
                }
                let afterClose = skipBalancedBracket(
                    in: following, from: 0, open: .symbol(.lParen), close: .symbol(.rParen)
                )
                return afterClose == following.count
                    || (afterClose < following.count && following[afterClose].kind == .symbol(.colon))
            }
        }
        return false
    }

    func propertyHeadTokens(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        includingTrailingLambdaTokens: Bool = false
    ) -> [Token] {
        var tokens: [Token] = []
        var inlineAccessorScanEnd = 0
        var enteredNestedBlock = false
        let children = Array(arena.children(of: nodeID))
        for (childIndex, child) in children.enumerated() {
            switch child {
            case let .token(tokenID):
                if let token = resolveToken(tokenID, in: arena) {
                    if !enteredNestedBlock {
                        switch token.kind {
                        case .softKeyword(.get), .softKeyword(.set):
                            if let idx = inlineAccessorStartIndex(in: tokens + [token]) {
                                return droppingTrailingAccessorModifiers(Array(tokens.prefix(idx)), interner: interner)
                            }
                            if isSiblingBlockAccessorHeader(
                                at: childIndex, in: children, arena: arena, previous: tokens.last
                            ) {
                                return droppingTrailingAccessorModifiers(tokens, interner: interner)
                            }
                        default:
                            break
                        }
                    }
                    tokens.append(token)
                    if !enteredNestedBlock {
                        inlineAccessorScanEnd = tokens.count
                    }
                }
            case let .node(childID):
                let childKind = arena.node(childID).kind
                if childKind == .propertyAccessor {
                    let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
                    if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
                        return droppingTrailingAccessorModifiers(Array(tokens.prefix(idx)), interner: interner)
                    }
                    return droppingTrailingAccessorModifiers(tokens, interner: interner)
                }
                if childKind == .block {
                    let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
                    if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
                        return droppingTrailingAccessorModifiers(Array(tokens.prefix(idx)), interner: interner)
                    }
                    // Do not scan tokens from a trailing lambda for inline
                    // accessors: a call such as `map.get(key)` uses the same
                    // soft keyword spelling as a property `get()` accessor.
                    enteredNestedBlock = true
                    // Genuine get()/set() and explicit-backing-field bodies are
                    // always wrapped as `.propertyAccessor` (see
                    // parsePropertyAccessor/parseExplicitBackingField), handled
                    // above -- a bare `.block` sibling here can only be a
                    // trailing-lambda call argument that `parseTail` split off
                    // while still inside the initializer expression (e.g.
                    // `= Comparator<Int> { a, b -> a - b }`).
                    //
                    // Only recurse for property initializers and delegate
                    // expressions, which explicitly opt in because a direct
                    // block is a trailing call argument. Delegate lowering
                    // still stores that same lambda body in
                    // `PropertyDecl.delegateBody` for its existing
                    // synthetic/runtime path.
                    guard includingTrailingLambdaTokens else {
                        return tokens
                    }
                    tokens.append(contentsOf: collectTokens(from: childID, in: arena))
                    continue
                }
            }
        }
        let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
        if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
            return droppingTrailingAccessorModifiers(Array(tokens.prefix(idx)), interner: interner)
        }
        return tokens
    }

    private func droppingTrailingAccessorModifiers(_ tokens: [Token], interner: StringInterner) -> [Token] {
        guard let start = trailingAccessorModifierStart(in: tokens, interner: interner) else {
            return tokens
        }
        return Array(tokens[..<start])
    }

    func trailingAccessorModifierStart(in tokens: [Token], interner: StringInterner) -> Int? {
        var candidates: [Int] = []
        var boundaryIndex = -1
        var depth = BracketDepth()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.at),
               let parsed = AnnotationParsingSupport.parseAnnotation(
                   from: tokens, start: index, interner: interner, allowUseSiteTarget: true
               )
            {
                if depth.isAtTopLevel {
                    candidates.append(index)
                }
                index = parsed.nextIndex
                continue
            }
            if depth.isAtTopLevel {
                switch token.kind {
                case .symbol(.colon), .symbol(.assign), .softKeyword(.by):
                    boundaryIndex = index
                default:
                    break
                }
                if isAccessorModifierKeyword(token.kind) {
                    candidates.append(index)
                }
            }
            depth.track(token.kind)
            index += 1
        }
        for start in candidates {
            if start > 0 {
                switch tokens[start - 1].kind {
                case .symbol(.dot), .symbol(.questionDot), .symbol(.arrow):
                    continue
                default:
                    break
                }
            }
            var cursor = start
            var valid = true
            while cursor < tokens.count {
                let kind = tokens[cursor].kind
                if kind == .symbol(.at),
                   let parsed = AnnotationParsingSupport.parseAnnotation(
                       from: tokens, start: cursor, interner: interner,
                       allowUseSiteTarget: true
                   )
                {
                    cursor = parsed.nextIndex
                } else if isAccessorModifierKeyword(kind) {
                    cursor += 1
                } else {
                    valid = false
                    break
                }
            }
            guard valid else { continue }
            var segmentHasRealToken = false
            var segmentIndex = boundaryIndex + 1
            while segmentIndex < start {
                if tokens[segmentIndex].kind == .symbol(.at),
                   let parsed = AnnotationParsingSupport.parseAnnotation(
                       from: tokens, start: segmentIndex, interner: interner,
                       allowUseSiteTarget: true
                   )
                {
                    segmentIndex = parsed.nextIndex
                    continue
                }
                segmentHasRealToken = true
                break
            }
            if segmentHasRealToken {
                return start
            }
        }
        return nil
    }

    func isAccessorModifierKeyword(_ kind: TokenKind) -> Bool {
        switch kind {
        case .keyword(.public), .keyword(.private), .keyword(.internal),
             .keyword(.protected), .keyword(.inline):
            true
        default:
            false
        }
    }

    private func collectPropertyTypeTokens(afterColonIndex colonIndex: Int, tokens: [Token]) -> [Token] {
        var typeTokens: [Token] = []
        var depth = BracketDepth()
        var index = colonIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                    break
                }
                if token.kind == .softKeyword(.by) { break }
                if token.kind == .keyword(.inline), !typeTokens.isEmpty,
                   typeTokens.last?.kind != .symbol(.dot),
                   typeTokens.last?.kind != .symbol(.arrow) { break }
                if token.kind == .softKeyword(.where), !typeTokens.isEmpty,
                   typeTokens.last?.kind != .symbol(.dot), index + 2 < tokens.count,
                   TypeRefParserCore.isTypeLikeNameToken(tokens[index + 1].kind),
                   tokens[index + 2].kind == .symbol(.colon) { break }
            }
            depth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }
        return typeTokens
    }

    func firstFunctionParameterCloseParen(in tokens: [Token]) -> Int? {
        guard let openIndex = functionParameterOpenParenIndex(in: tokens) else {
            return nil
        }
        let afterClose = skipBalancedBracket(in: tokens, from: openIndex, open: .symbol(.lParen), close: .symbol(.rParen))
        guard afterClose > openIndex else {
            return nil
        }
        return afterClose - 1
    }

    func functionKeywordIndex(in tokens: [Token]) -> Int? {
        firstTopLevelKeywordIndex(in: tokens, matching: [.fun])
    }

    func functionParameterOpenParenIndex(in tokens: [Token]) -> Int? {
        guard let funIndex = functionKeywordIndex(in: tokens) else {
            return nil
        }
        var index = funIndex + 1
        if index < tokens.count, tokens[index].kind == .symbol(.lessThan) {
            index = skipBalancedBracket(
                in: tokens,
                from: index,
                open: .symbol(.lessThan),
                close: .symbol(.greaterThan)
            )
        }
        if let afterReceiver = indexAfterParenthesizedReceiver(in: tokens, from: index) {
            index = afterReceiver
        }
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                return index
            }
            if kind == .symbol(.lBrace) {
                return nil
            }
            index += 1
        }
        return nil
    }

    func indexAfterParenthesizedReceiver(in tokens: [Token], from index: Int) -> Int? {
        guard index < tokens.count, tokens[index].kind == .symbol(.lParen) else {
            return nil
        }
        var probe = skipBalancedBracket(
            in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen)
        )
        if probe < tokens.count, tokens[probe].kind == .symbol(.question) {
            probe += 1
        }
        guard probe < tokens.count,
              tokens[probe].kind == .symbol(.dot) || tokens[probe].kind == .symbol(.questionDot)
        else {
            return nil
        }
        return probe + 1
    }

    func parseTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard !tokens.isEmpty else {
            return nil
        }
        let options = TypeRefParserCore.Options.declaration
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics
        ) else {
            return nil
        }
        guard parsed.consumed == tokens.count else {
            let unexpectedToken = tokens[parsed.consumed]
            let message = unexpectedToken.kind == .symbol(.bang)
                ? "Platform type suffix '!' is not valid in source type references."
                : "Unexpected token after type reference."
            diagnostics?.error(
                "KSWIFTK-PARSE-0024",
                message,
                range: unexpectedToken.range
            )
            return nil
        }
        return parsed.ref
    }
}
