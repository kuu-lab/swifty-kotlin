extension KotlinParser {
    func parseDeclaration(isLocal: Bool = false) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: true)
        }
        defer { leaveNesting() }

        var modifierChildren: [SyntaxChild] = []
        var modifierRange = RangeAccumulator()
        func consumeContextClause(_ clause: LeanParser.DeclarationContextClause) {
            guard clause != .absent else { return }
            _ = consumeToken(into: &modifierChildren, range: &modifierRange)
            if clause == .group {
                let group = parseBalancedGroup(opening: .lParen, closing: .rParen)
                modifierChildren.append(.node(group))
                modifierRange.append(childRange(.node(group)))
            } else {
                insertMissingToken(
                    expected: .symbol(.lParen),
                    into: &modifierChildren,
                    range: &modifierRange,
                    code: "KSWIFTK-PARSE-0001",
                    message: "Expected '(' after context."
                )
            }
        }
        if let head = LeanParser.declarationPrefixHead(self) {
            switch head {
            case let .contextFirst(clause):
                consumeContextClause(clause)
                parseLeadingDeclarationPrefix(into: &modifierChildren, range: &modifierRange)
            case let .prefixFirst(consumed, recovered, clause):
                appendScannedLeadingPrefix(consumed, recovered: recovered, into: &modifierChildren, range: &modifierRange)
                consumeContextClause(clause)
            }
            parseLeadingDeclarationPrefix(into: &modifierChildren, range: &modifierRange)
        }
        while let dispatch = LeanParser.declarationDispatch(self, hasPrefix: !modifierChildren.isEmpty) {
            switch dispatch {
            case .classDecl:
                return parseNamedDeclaration(
                    kind: .classDecl, leadingChildren: modifierChildren, leadingRange: modifierRange.value
                )
            case .objectDecl, .companionObject:
                if dispatch == .companionObject {
                    _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                }
                return parseNamedDeclaration(
                    kind: .objectDecl, leadingChildren: modifierChildren, leadingRange: modifierRange.value
                )
            case .interfaceDecl, .funInterface:
                if dispatch == .funInterface {
                    _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                }
                return parseNamedDeclaration(
                    kind: .interfaceDecl, leadingChildren: modifierChildren, leadingRange: modifierRange.value
                )
            case .function:
                return parseFunctionDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .property:
                return parsePropertyDeclaration(
                    leadingChildren: modifierChildren, leadingRange: modifierRange.value,
                    allowsBodylessAccessors: !isLocal
                )
            case .typeAlias:
                return parseTypeAliasDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .enumDecl:
                return parseEnumDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .packageHeader:
                return parsePackageHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .importHeader:
                return parseImportHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .constructor:
                return parseConstructorDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
            case .companionBlock:
                _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                let body: SyntaxChild = .node(parseBlock())
                modifierChildren.append(body)
                modifierRange.append(childRange(body))
                return arena.appendNode(
                    kind: .statement, range: modifierRange.value ?? invalidRange, modifierChildren
                )
            case .retryAfterCompanion:
                _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                parseLeadingDeclarationPrefix(into: &modifierChildren, range: &modifierRange)
            case .retryAfterEnum:
                _ = consumeToken(into: &modifierChildren, range: &modifierRange)
            case .statement:
                return parseStatement(inBlock: false)
            case .prefixedStatement, .invalidAccessor:
                if dispatch == .invalidAccessor {
                    diagnostics.error(
                        "KSWIFTK-PARSE-0002", "Expecting member declaration.", range: stream.peek().range
                    )
                }
                parseTail(inBlock: false, into: &modifierChildren, range: &modifierRange)
                return arena.appendNode(
                    kind: .statement, range: modifierRange.value ?? invalidRange, modifierChildren
                )
            }
        }
        return arena.appendNode(kind: .statement, range: modifierRange.value ?? invalidRange, modifierChildren)
    }

    func parsePackageHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(isImport: false, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    func parseImportHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(isImport: true, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    private func parseHeaderDeclaration(
        isImport: Bool, leadingChildren: [SyntaxChild], leadingRange: SourceRange?
    ) -> NodeID {
        var range = RangeAccumulator(value: leadingRange)
        var children = leadingChildren
        if let plan = LeanParser.headerPlan(self, isImport: isImport) {
            if plan.hasKeyword {
                _ = consumeToken(into: &children, range: &range)
            } else {
                let keyword: TokenKind = .keyword(isImport ? .import : .package)
                insertMissingToken(expected: keyword, into: &children, range: &range, code: "KSWIFTK-PARSE-0001", message: "Expected \(keyword).")
            }
            if plan.pathCount == 0 {
                insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0003", message: "Expected name in package/import path.")
            }
            for _ in 0..<(plan.pathCount + plan.alias.rawValue) {
                _ = consumeToken(into: &children, range: &range)
            }
            if plan.alias == .missing {
                insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0005", message: "Expected alias name after 'as'.")
            }
            if plan.hasTerminator {
                _ = consumeToken(into: &children, range: &range)
            }
        }
        return arena.appendNode(kind: isImport ? .importHeader : .packageHeader, range: range.value ?? invalidRange, children)
    }

    func parseNamedDeclaration(
        kind: SyntaxKind,
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)
        let supportsTypeParameters = kind == .classDecl || kind == .interfaceDecl

        let isCompanionObject = kind == .objectDecl && leadingChildren.contains(where: { child in
            if case let .token(tokenID) = child,
               let token = arena.token(tokenID),
               case .keyword(.companion) = token.kind
            {
                return true
            }
            return false
        })

        _ = consumeToken(into: &children, range: &range)
        let nameKind = stream.peek().kind
        let hasName = isCompanionObject ? LeanParser.isCompanionObjectName(self, kind: nameKind) : isIdentifierLike(nameKind)
        if hasName {
            _ = consumeToken(into: &children, range: &range)
        } else if !isCompanionObject {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected declaration name.", severity: .error)
        }
        if supportsTypeParameters, canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        if kind != .classDecl, case .symbol(.lParen) = stream.peek().kind {
            diagnostics.error(
                "KSWIFTK-PARSE-0006",
                "Object and interface declarations cannot have primary constructor parameters.",
                range: stream.peek().range
            )
            let parameters = parseBalancedGroup(
                opening: .lParen, closing: .rParen, allowsValueParameters: true
            )
            children.append(.node(parameters))
            range.append(childRange(.node(parameters)))
        }
        // A primary-constructor annotation may start on the next line. Prove
        // that the prefix ends in `constructor (` before consuming it, so a
        // following annotated declaration remains outside this class.
        if kind == .classDecl, LeanParser.startsPrimaryConstructorHeader(self) {
            parseLeadingDeclarationPrefix(into: &children, range: &range)
            _ = consumeToken(into: &children, range: &range)
            let parameters = parseBalancedGroup(
                opening: .lParen, closing: .rParen, allowsValueParameters: true
            )
            children.append(.node(parameters))
            range.append(childRange(.node(parameters)))
        }
        parsePostDeclarationTail(
            into: &children,
            range: &range,
            includeBlock: kind == .classDecl || kind == .interfaceDecl || kind == .objectDecl,
            allowsClassHeaderColon: kind == .classDecl,
            allowsClassDelegation: kind == .classDecl || kind == .objectDecl,
            allowsWhereClauseContinuation: supportsTypeParameters
        )

        return arena.appendNode(
            kind: kind,
            range: range.value ?? invalidRange, children
        )
    }

    func parseFunctionDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)
        var hasTypeParameters = false

        _ = consumeToken(into: &children, range: &range)
        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            hasTypeParameters = true
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        consumeLeadingPrefix(.receiver, into: &children, range: &range)
        if offsetAfterParenthesizedReceiver(from: 0) != nil {
            let receiverGroup = parseBalancedGroup(opening: .lParen, closing: .rParen)
            children.append(.node(receiverGroup))
            range.append(childRange(.node(receiverGroup)))
            if case .symbol(.question) = stream.peek().kind {
                _ = consumeToken(into: &children, range: &range)
            }
            _ = consumeToken(into: &children, range: &range)
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected function name.", severity: .error)
        }

        if case .symbol(.lParen) = stream.peek().kind {
            let params = parseBalancedGroup(opening: .lParen, closing: .rParen, allowsValueParameters: true)
            children.append(.node(params))
            range.append(childRange(.node(params)))
        } else if isIdentifierLike(stream.peek().kind) || stream.peek().kind == .keyword(.fun),
                  !hasLeadingNewline(stream.peek())
        {
            // `fun infix f(x: Int)`: a modifier written after `fun` is parsed as
            // the function name and the real name follows it. kotlinc rejects
            // this with "Expecting '('. A repeated `fun` (`fun tailrec fun f`)
            // must error the same way instead of being silently absorbed.
            diagnostics.error(
                "KSWIFTK-PARSE-0002",
                "Expecting '('.",
                range: stream.peek().range
            )
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseBlock()
            children.append(.node(body))
            range.append(childRange(.node(body)))
        } else {
            parseTail(
                inBlock: false,
                into: &children,
                range: &range,
                allowsDeclarationAssignment: true,
                allowsFunctionWhereClause: hasTypeParameters,
                allowsDeclaredTypeColon: true,
                stopsAtFunctionDelegation: true
            )
            if case .symbol(.lBrace) = stream.peek().kind,
               hasLeadingNewline(stream.peek()),
               lastConsumedToken?.kind != .symbol(.semicolon),
               !children.contains(where: { child in
                   guard case let .token(tokenID) = child else { return false }
                   return arena.token(tokenID)?.kind == .symbol(.assign)
               })
            {
                let body = parseBlock()
                children.append(.node(body))
                range.append(childRange(.node(body)))
            }
        }

        return arena.appendNode(
            kind: .funDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func offsetAfterParenthesizedReceiver(from start: Int, maxDistance: Int? = nil) -> Int? {
        guard stream.peek(start).kind == .symbol(.lParen) else { return nil }
        var offset = offsetPastBalancedGroup(
            from: start, maxDistance: maxDistance
        )
        if stream.peek(offset).kind == .symbol(.question) {
            offset += 1
        }
        switch stream.peek(offset).kind {
        case .symbol(.dot), .symbol(.questionDot):
            return offset + 1
        default:
            return nil
        }
    }

    func parsePropertyDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil,
        allowsBodylessAccessors: Bool = true
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            let parameters = parseTypeArguments()
            children.append(.node(parameters))
            range.append(childRange(.node(parameters)))
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
            let token = stream.peek()
            let isStrayQuestion: Bool
            switch token.kind {
            case .symbol(.questionColon):
                isStrayQuestion = true
            case .symbol(.question):
                isStrayQuestion = stream.peek(1).kind != .symbol(.dot)
            default:
                isStrayQuestion = false
            }
            if isStrayQuestion {
                diagnostics.error(
                    "KSWIFTK-PARSE-0019",
                    "Unexpected '?' after property name.",
                    range: token.range
                )
            }
        } else if case .symbol(.lParen) = stream.peek().kind {
        } else if case .symbol(.lBracket) = stream.peek().kind {
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected property name.", severity: .error)
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseBlock()
            children.append(.node(body))
            range.append(childRange(.node(body)))
        } else {
            parseTail(
                inBlock: false,
                into: &children,
                range: &range,
                allowsDeclarationAssignment: true,
                allowsPropertyDelegation: true,
                allowsDeclaredTypeColon: true
            )
            var absorbedAnyAccessorOrField = false
            var absorbedBareDefaultAccessor = false
            while true {
                // A `;` does not separate accessor lines the way `semi` does in
                // the rest of the grammar. Right after a property head with no
                // accessor it is tolerated only on the same line —
                // `var x = 1; get() = 2` compiles while `var x = 1;\nget` is
                // kotlinc's "Expecting member declaration". Once the accessor
                // list has started — including an inline header the head line
                // itself carried (`var f: Int get() = x;\nset(v) {}`) — it
                // always separates. A bare `get`/`set` accessor ends the list
                // instead (`get; set` is rejected even on the same line).
                if lastConsumedToken?.kind == .symbol(.semicolon),
                   absorbedBareDefaultAccessor
                       || (!absorbedAnyAccessorOrField
                           && !propertyTailContainsAccessorHeader(children)
                           && hasLeadingNewline(stream.peek()))
                {
                    break
                }
                if LeanParser.isExplicitBackingFieldStart(self) {
                    parseExplicitBackingField(into: &children, range: &range)
                    absorbedBareDefaultAccessor = false
                } else if isPropertyAccessorStart(allowsBodyless: allowsBodylessAccessors) {
                    absorbedBareDefaultAccessor = parsePropertyAccessor(into: &children, range: &range)
                } else {
                    break
                }
                absorbedAnyAccessorOrField = true
            }
        }

        return arena.appendNode(
            kind: .propertyDecl,
            range: range.value ?? invalidRange, children
        )
    }

    @discardableResult
    private func parsePropertyAccessor(into children: inout [SyntaxChild], range: inout RangeAccumulator) -> Bool {
        var accessorChildren: [SyntaxChild] = []
        var accessorRange = RangeAccumulator()

        parseLeadingDeclarationPrefix(into: &accessorChildren, range: &accessorRange)
        parseTail(inBlock: false, into: &accessorChildren, range: &accessorRange)

        let accessorNodeRange = accessorRange.value ?? invalidRange
        let nodeID = arena.appendNode(
            kind: .propertyAccessor,
            range: accessorNodeRange,
            accessorChildren
        )
        children.append(.node(nodeID))
        range.append(accessorNodeRange)

        return accessorChildren.allSatisfy { child in
            guard case let .token(tokenID) = child,
                  let token = arena.token(tokenID)
            else {
                return false
            }
            switch token.kind {
            case .softKeyword(.get), .softKeyword(.set), .symbol(.semicolon):
                return true
            default:
                return false
            }
        }
    }

    private func parseExplicitBackingField(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
        var fieldChildren: [SyntaxChild] = []
        var fieldRange = RangeAccumulator()

        parseTail(inBlock: false, into: &fieldChildren, range: &fieldRange)

        let nodeRange = fieldRange.value ?? invalidRange
        let nodeID = arena.appendNode(
            kind: .propertyAccessor,
            range: nodeRange,
            fieldChildren
        )
        children.append(.node(nodeID))
        range.append(nodeRange)
    }

    func parseTypeAliasDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected typealias name.", severity: .error)
        }
        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        parseTail(inBlock: false, into: &children, range: &range)

        return arena.appendNode(
            kind: .typeAliasDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parseEnumDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)
        if case .keyword(.class) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
        }
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        } else {
            insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0002", message: "Expected enum name.", severity: .error)
        }

        if canStartTypeArgumentsInternal(hasAnchorToken: lastConsumedToken != nil) {
            children.append(.node(parseTypeArguments()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }
        if case .symbol(.lParen) = stream.peek().kind {
            let params = parseBalancedGroup(
                opening: .lParen, closing: .rParen, allowsValueParameters: true
            )
            children.append(.node(params))
            range.append(childRange(.node(params)))
        }
        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseEnumBody()
            children.append(.node(body))
            range.append(childRange(.node(body)))
        } else if !parseEnumHeaderTail(into: &children, range: &range) {
            parseTail(inBlock: false, into: &children, range: &range)
        }

        return arena.appendNode(
            kind: .classDecl,
            range: range.value ?? invalidRange, children
        )
    }

    func parseEnumBody() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        guard consumeIfSymbol(.lBrace, into: &children, range: &range) else {
            return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
        }

        // The first top-level `;` ends the entry list; anything after it is a
        // class member. Without this, an identifier-like soft keyword such as
        // `init` in `A, B; init { ... }` was parsed as a third enum entry.
        var entryListEnded = false
        var closed = false
        while !stream.atEOF() {
            let token = stream.peek()
            if case .symbol(.rBrace) = token.kind {
                _ = consumeToken(into: &children, range: &range)
                closed = true
                break
            }

            if LeanParser.enumBodyStartsDeclaration(self) {
                children.append(.node(parseDeclaration()))
                continue
            }
            if !entryListEnded,
               isIdentifierLike(token.kind) || LeanParser.enumEntryStartsAfterLeadingAnnotations(self)
            {
                children.append(.node(parseEnumEntryDeclaration()))
                continue
            }
            if token.kind == .symbol(.comma) || token.kind == .symbol(.semicolon) {
                if token.kind == .symbol(.semicolon) {
                    entryListEnded = true
                }
                _ = consumeToken(into: &children, range: &range)
                continue
            }
            children.append(.node(parseStatement(inBlock: true)))
        }

        if !closed {
            reportUnclosedBlock(lastRange: range.value)
        }
        return arena.appendNode(kind: .block, range: range.value ?? invalidRange, children)
    }

    func parseEnumEntryDeclaration() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        consumeLeadingPrefix(.annotations, into: &children, range: &range)
        if isIdentifierLike(stream.peek().kind) {
            _ = consumeToken(into: &children, range: &range)
        }
        if case .symbol(.lParen) = stream.peek().kind {
            let args = parseBalancedGroup(opening: .lParen, closing: .rParen)
            children.append(.node(args))
            range.append(childRange(.node(args)))
        }
        if case .symbol(.lBrace) = stream.peek().kind {
            let body = parseBlock()
            children.append(.node(body))
            range.append(childRange(.node(body)))
        }

        return arena.appendNode(
            kind: .enumEntry,
            range: range.value ?? invalidRange, children
        )
    }

    /// Consumes an enum header such as ": Interface<T>" until its class body,
    /// then parses that body with the enum-specific entry parser. A generic
    /// declaration tail would otherwise parse the body as an ordinary block,
    /// making entries with anonymous class bodies indistinguishable from calls.
    @discardableResult
    private func parseEnumHeaderTail(
        into children: inout [SyntaxChild],
        range: inout RangeAccumulator
    ) -> Bool {
        var depth = BracketDepth()
        var delegateBraceTracker = DelegateExpressionBraceTracker()

        while !stream.atEOF() {
            let token = stream.peek()
            let atTopLevel = depth.isTopLevel && depth.angle == 0
            if atTopLevel, case .symbol(.lBrace) = token.kind {
                if delegateBraceTracker.braceContinuesDelegateExpression() {
                    let braceToken = consumeToken(into: &children, range: &range)
                    delegateBraceTracker.note(braceToken.kind, atTopLevel: true)
                    depth.track(token.kind)
                    continue
                }
                let body = parseEnumBody()
                children.append(.node(body))
                range.append(childRange(.node(body)))
                return true
            }
            if atTopLevel, case .symbol(.rBrace) = token.kind {
                return false
            }
            if atTopLevel,
               hasLeadingNewline(token),
               isDeclarationStart(token.kind)
            {
                return false
            }

            let consumedToken = consumeToken(into: &children, range: &range)
            delegateBraceTracker.note(consumedToken.kind, atTopLevel: atTopLevel)
            depth.track(token.kind)
        }
        return false
    }

    func parseConstructorDeclaration(
        leadingChildren: [SyntaxChild] = [],
        leadingRange: SourceRange? = nil
    ) -> NodeID {
        var children: [SyntaxChild] = leadingChildren
        var range = RangeAccumulator(value: leadingRange)

        _ = consumeToken(into: &children, range: &range)

        if case .symbol(.lParen) = stream.peek().kind {
            children.append(.node(parseBalancedGroup(
                opening: .lParen, closing: .rParen, allowsValueParameters: true
            )))
            if let last = children.last {
                range.append(childRange(last))
            }
        }

        for _ in 0..<LeanParser.constructorTailCount(self) {
            _ = consumeToken(into: &children, range: &range)
        }

        if case .symbol(.lBrace) = stream.peek().kind {
            children.append(.node(parseBlock()))
            if let last = children.last {
                range.append(childRange(last))
            }
        }

        return arena.appendNode(kind: .constructorDecl, range: range.value ?? invalidRange, children)
    }

    func parsePostDeclarationTail(
        into children: inout [SyntaxChild], range: inout RangeAccumulator,
        includeBlock: Bool, allowsClassHeaderColon: Bool = false,
        allowsClassDelegation: Bool = false,
        allowsWhereClauseContinuation: Bool = false
    ) {
        if case .symbol(.lBrace) = stream.peek().kind {
            if includeBlock {
                let body = parseBlock(isClassBody: true)
                children.append(.node(body))
                range.append(childRange(.node(body)))
            } else {
                _ = consumeToken(into: &children, range: &range)
            }
            return
        }
        if LeanParser.stopsDeclarationHeaderAtNewline(
            self,
            includeBlock: includeBlock,
            allowsClassHeaderColon: allowsClassHeaderColon,
            allowsClassDelegation: allowsClassDelegation
        ) {
            return
        }
        parseTail(
            inBlock: false, into: &children, range: &range,
            allowsClassHeaderColon: allowsClassHeaderColon,
            allowsClassDelegation: allowsClassDelegation,
            allowsWhereClauseContinuation: allowsWhereClauseContinuation,
            isClassBody: includeBlock
        )
        if includeBlock, stream.peek().kind == .symbol(.lBrace),
           lastConsumedToken?.kind != .symbol(.semicolon),
           !children.contains(where: { child in
               guard case let .node(id) = child else { return false }
               return arena.node(id).kind == .block
           })
        {
            let body = parseBlock(isClassBody: true)
            children.append(.node(body))
            range.append(childRange(.node(body)))
        }
    }
}
