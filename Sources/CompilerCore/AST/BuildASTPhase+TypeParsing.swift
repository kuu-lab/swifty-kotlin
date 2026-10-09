
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

        if receiverStart >= receiverSeparatorIndex {
            return nil
        }

        var receiverTokens = Array(tokens[receiverStart ..< receiverSeparatorIndex])
        if receiverSeparatorToken?.kind == .symbol(.questionDot),
           let separatorRange = receiverSeparatorToken?.range
        {
            receiverTokens.append(Token(kind: .symbol(.question), range: separatorRange))
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationContextReceivers(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ContextReceiverDecl] {
        let allTokens = collectTokens(from: nodeID, in: arena)
        // Context receivers are declaration modifiers, so they always precede `fun`.
        // Restricting the scan keeps a `context(...)` function type in the parameter
        // list — or a function literally named `context` — from being mistaken for
        // a declaration-level context receiver.
        let tokens = if let funIndex = allTokens.firstIndex(where: { $0.kind == .keyword(.fun) }) {
            Array(allTokens[..<funIndex])
        } else {
            allTokens
        }
        guard let contextIndex = tokens.firstIndex(where: { $0.kind == .softKeyword(.context) }) else {
            return []
        }
        guard contextIndex + 1 < tokens.count, tokens[contextIndex + 1].kind == .symbol(.lParen) else {
            return []
        }
        var index = contextIndex + 2
        var depth = 1
        var current: [Token] = []
        var items: [ContextReceiverDecl] = []
        while index < tokens.count, depth > 0 {
            let token = tokens[index]
            if token.kind == .symbol(.lParen) {
                depth += 1
                current.append(token)
            } else if token.kind == .symbol(.rParen) {
                depth -= 1
                if depth == 0 {
                    if let item = parseContextReceiverItem(from: current, interner: interner, astArena: astArena) {
                        items.append(ContextReceiverDecl(name: item.name, type: item.ref))
                    }
                    break
                }
                current.append(token)
            } else if token.kind == .symbol(.comma), depth == 1 {
                if let item = parseContextReceiverItem(from: current, interner: interner, astArena: astArena) {
                    items.append(ContextReceiverDecl(name: item.name, type: item.ref))
                }
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(token)
            }
            index += 1
        }
        return items
    }

    /// Context parameters may carry a `name:` or `_:` prefix (`context(ctx: Context)` /
    /// `context(_: Context)`). Split the leading `name :` off so the receiver type still
    /// parses.
    private func parseContextReceiverItem(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> (name: InternedString?, ref: TypeRefID)? {
        var name: InternedString?
        var typeTokens = tokens
        if typeTokens.count > 2,
           typeTokens[1].kind == .symbol(.colon)
        {
            switch typeTokens[0].kind {
            case let .identifier(ident):
                if interner.resolve(ident) != "_" {
                    name = ident
                }
                typeTokens = Array(typeTokens.dropFirst(2))
            case let .backtickedIdentifier(ident):
                name = ident
                typeTokens = Array(typeTokens.dropFirst(2))
            default:
                break
            }
        }
        guard let ref = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            return nil
        }
        return (name, ref)
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

        var index = closeParenIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.assign) || token.kind == .symbol(.lBrace) {
                return nil
            }
            if token.kind == .symbol(.colon) {
                index += 1
                break
            }
            index += 1
        }

        guard index < tokens.count else {
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

        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
    }

    func declarationPropertyReceiverType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)

        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return nil
        }

        // Look for the last top-level dot after the val/var keyword, skipping angle brackets
        // for generic receiver types (e.g. `val List<Int>.head`). This handles qualified
        // receiver types like `val kotlin.String.firstChar: Char` correctly.
        var lastDotIndex: Int?
        var depth = BracketDepth()
        for index in (valVarIndex + 1) ..< tokens.count {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0 {
                if token.kind == .symbol(.dot) {
                    lastDotIndex = index
                } else if token.kind == .symbol(.colon)
                    || token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                {
                    break
                }
            }
        }
        guard let dotIndex = lastDotIndex else {
            return nil
        }

        let receiverTokens = Array(tokens[(valVarIndex + 1) ..< dotIndex])
        guard !receiverTokens.isEmpty else {
            return nil
        }
        return parseTypeRef(from: receiverTokens, interner: interner, astArena: astArena)
    }

    func declarationPropertyNameAfterDot(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> InternedString {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)

        guard let valVarIndex = tokens.firstIndex(where: {
            $0.kind == .keyword(.val) || $0.kind == .keyword(.var)
        }) else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        // Find the last top-level dot before `:`, `=`, or `{`.
        // This handles qualified receiver types like `val kotlin.String.firstChar: Char`.
        var depth = BracketDepth()
        var lastDotIndex: Int?
        for index in (valVarIndex + 1) ..< tokens.count {
            let token = tokens[index]
            depth.track(token.kind)
            if depth.angle == 0 {
                if token.kind == .symbol(.dot) {
                    lastDotIndex = index
                } else if token.kind == .symbol(.colon)
                    || token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                {
                    break
                }
            }
        }
        guard let dotIndex = lastDotIndex, dotIndex + 1 < tokens.count else {
            return declarationName(from: nodeID, in: arena, interner: interner)
        }

        let nameToken = tokens[dotIndex + 1]
        if let name = internedIdentifier(from: nameToken, interner: interner) {
            return name
        }
        return declarationName(from: nodeID, in: arena, interner: interner)
    }

    func declarationPropertyType(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = propertyHeadTokens(from: nodeID, in: arena)
        var sawName = false
        var colonIndex: Int?
        for (index, token) in tokens.enumerated() {
            if !sawName {
                switch token.kind {
                case .keyword(.val), .keyword(.var):
                    continue
                default:
                    if TypeRefParserCore.isTypeLikeNameToken(token.kind) {
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
        return parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
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
                    // Stop before inline `get(`/`set(` accessor keywords so that
                    // type and initializer parsing don't consume accessor tokens.
                    if !enteredNestedBlock {
                        switch token.kind {
                        case .softKeyword(.get), .softKeyword(.set):
                            if let idx = inlineAccessorStartIndex(in: tokens + [token]) {
                                return Array(tokens.prefix(idx))
                            }
                            // `var p: Int get() { ... }` keeps the getter's
                            // block as a sibling node, so the direct tokens
                            // end at `get()` and the scan above cannot see a
                            // body. Use the following children instead.
                            if isSiblingBlockAccessorHeader(
                                at: childIndex, in: children, arena: arena, previous: tokens.last
                            ) {
                                return tokens
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
                    // A later accessor child may follow an inline expression
                    // getter. Its '=' belongs to the getter, not an initializer.
                    let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
                    if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
                        return Array(tokens.prefix(idx))
                    }
                    return tokens
                }
                if childKind == .block {
                    // An expression getter may end in a lambda sibling block.
                    // Strip its complete `get() =` header before returning the
                    // property head, just as for a propertyAccessor child.
                    let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
                    if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
                        return Array(tokens.prefix(idx))
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
        // Final check: scan only the direct-token prefix for inline accessor
        // start.  Recursed trailing-lambda tokens may contain calls to `get` or
        // `set`, which are not property accessors.
        let inlineAccessorTokens = Array(tokens.prefix(inlineAccessorScanEnd))
        if let idx = inlineAccessorStartIndex(in: inlineAccessorTokens) {
            return Array(tokens.prefix(idx))
        }
        return tokens
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
                if case .softKeyword(.by) = token.kind { break }
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

    /// The scan is anchored at the `fun` keyword to avoid picking annotation
    /// argument lists that appear before the declaration keyword.
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
        // `fun (() -> R).name(` / `fun (T)?.name(`: a parenthesized receiver
        // type precedes the function name, so its `(` is not the parameter list.
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
        return parsed.consumed == tokens.count ? parsed.ref : nil
    }
}
