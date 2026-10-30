extension KotlinParser {
    func parseDeclaration(isLocal: Bool = false) -> NodeID {
        guard enterNesting() else {
            return recoverFromNestingLimit(inBlock: true)
        }
        defer { leaveNesting() }

        var modifierChildren: [SyntaxChild] = []
        var modifierRange = RangeAccumulator()
        if case .softKeyword(.context) = stream.peek().kind {
            _ = consumeToken(into: &modifierChildren, range: &modifierRange)
            if case .symbol(.lParen) = stream.peek().kind {
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
        parseLeadingDeclarationPrefix(into: &modifierChildren, range: &modifierRange)
        companionDispatch: while true {
        let token = stream.peek()
        switch token.kind {
        case .keyword(.class):
            return parseNamedDeclaration(
                kind: .classDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.object):
            return parseNamedDeclaration(
                kind: .objectDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.interface):
            return parseNamedDeclaration(
                kind: .interfaceDecl,
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.fun):
            if stream.peek(1).kind == .keyword(.interface) {
                _ = consumeToken(into: &modifierChildren, range: &modifierRange)
                return parseNamedDeclaration(
                    kind: .interfaceDecl,
                    leadingChildren: modifierChildren,
                    leadingRange: modifierRange.value
                )
            }
            return parseFunctionDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.val), .keyword(.var):
            return parsePropertyDeclaration(
                leadingChildren: modifierChildren, leadingRange: modifierRange.value,
                allowsBodylessAccessors: !isLocal
            )
        case .keyword(.typealias):
            return parseTypeAliasDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.enum):
            return parseEnumDeclaration(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.package):
            return parsePackageHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.import):
            return parseImportHeader(leadingChildren: modifierChildren, leadingRange: modifierRange.value)
        case .keyword(.constructor), .softKeyword(.constructor):
            return parseConstructorDeclaration(
                leadingChildren: modifierChildren,
                leadingRange: modifierRange.value
            )
        case .keyword(.companion):
            _ = consumeToken(into: &modifierChildren, range: &modifierRange)
            if case .keyword(.object) = stream.peek().kind {
                return parseNamedDeclaration(
                    kind: .objectDecl,
                    leadingChildren: modifierChildren,
                    leadingRange: modifierRange.value
                )
            }
            if case .symbol(.lBrace) = stream.peek().kind {
                let body = parseBlock()
                modifierChildren.append(.node(body))
                modifierRange.append(childRange(.node(body)))
                return arena.appendNode(
                    kind: .statement,
                    range: modifierRange.value ?? invalidRange,
                    modifierChildren
                )
            }
            // Companion extensions can combine `companion` with ordinary
            // declaration modifiers, e.g. `companion operator fun C.invoke()`.
            parseLeadingDeclarationPrefix(into: &modifierChildren, range: &modifierRange)
            // Keep an otherwise invalid `companion` modifier attached so
            // downstream validation can report its declaration position.
            continue companionDispatch
        default:
            if !modifierChildren.isEmpty {
                // `get`/`set` after a modifier prefix is a misplaced accessor
                // (e.g. `private set var x`); accessors must follow the
                // property declaration. Diagnose, then recover into the
                // statement tail as before.
                if case let .softKeyword(soft) = token.kind,
                   soft == .get || soft == .set
                {
                    diagnostics.error(
                        "KSWIFTK-PARSE-0002",
                        "Expecting member declaration.",
                        range: token.range
                    )
                }
                let nextKind = stream.peek().kind
                if nextKind != .keyword(.package), nextKind != .keyword(.import) {
                    parseTail(inBlock: false, into: &modifierChildren, range: &modifierRange)
                }
                return arena.appendNode(kind: .statement, range: modifierRange.value ?? invalidRange, modifierChildren)
            }
            return parseStatement(inBlock: false)
        }
        }
    }

    func parsePackageHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.package), kind: .packageHeader, allowWildcard: false, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    func parseImportHeader(leadingChildren: [SyntaxChild] = [], leadingRange: SourceRange? = nil) -> NodeID {
        parseHeaderDeclaration(keyword: .keyword(.import), kind: .importHeader, allowWildcard: true, allowAlias: true, leadingChildren: leadingChildren, leadingRange: leadingRange)
    }

    func parseHeaderDeclaration(
        keyword: TokenKind,
        kind: SyntaxKind,
        allowWildcard: Bool,
        allowAlias: Bool = false,
        leadingChildren: [SyntaxChild],
        leadingRange: SourceRange?
    ) -> NodeID {
        var range = RangeAccumulator(value: leadingRange)
        var children: [SyntaxChild] = leadingChildren
        consumeIf(expected: keyword, into: &children, range: &range, code: "KSWIFTK-PARSE-0001")
        parseQualifiedPath(into: &children, range: &range, allowImportWildcard: allowWildcard, stopAtAs: allowAlias)
        if allowAlias, case .keyword(.as) = stream.peek().kind {
            _ = consumeToken(into: &children, range: &range)
            if isIdentifierLike(stream.peek().kind) {
                _ = consumeToken(into: &children, range: &range)
            } else {
                insertMissingToken(expected: .identifier(.invalid), into: &children, range: &range, code: "KSWIFTK-PARSE-0005", message: "Expected alias name after 'as'.")
            }
        }
        appendOptionalTerminator(into: &children, range: &range)
        return arena.appendNode(kind: kind, range: range.value ?? invalidRange, children)
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
        let hasName = isCompanionObject ? isCompanionObjectName(nameKind) : isIdentifierLike(nameKind)
        if hasName {
            _ = consumeToken(into: &children, range: &range)
        } else if !isCompanionObject {
            // Companion objects may omit the name (defaults to "Companion"),
            // so only emit a diagnostic for non-companion declarations.
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
        if kind == .classDecl, startsPrimaryConstructorHeader() {
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

    /// An optional companion name must be a simpleIdentifier. Leave hard
    /// keywords for the next member declaration, while allowing names after
    /// a newline and contextual or modifier keywords used as names.
    private func isCompanionObjectName(_ kind: TokenKind) -> Bool {
        switch kind {
        case .identifier, .backtickedIdentifier:
            true
        case let .softKeyword(keyword):
            keyword != .when
        case let .keyword(keyword):
            switch keyword {
            case .abstract, .annotation, .catch, .companion, .constructor, .crossinline,
                 .data, .dynamic, .enum, .external, .final, .finally, .import, .infix,
                 .inline, .inner, .internal, .lateinit, .noinline, .open, .operator,
                 .override, .private, .protected, .public, .reified, .sealed, .tailrec,
                 .vararg, .expect, .actual, .const, .suspend, .value:
                true
            default:
                false
            }
        default:
            false
        }
    }

    private func startsPrimaryConstructorHeader() -> Bool {
        var offset = 0
        while true {
            let kind = stream.peek(offset).kind
            if kind == .keyword(.constructor) || kind == .softKeyword(.constructor) {
                return stream.peek(offset + 1).kind == .symbol(.lParen)
            }
            if case let .keyword(keyword) = kind, Self.isDeclarationModifierKeyword(keyword) {
                offset += 1
                continue
            }
            guard kind == .symbol(.at) else { return false }
            guard let end = offsetPastAnnotationPrefix(from: offset) else { return false }
            offset = end
        }
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
        // Parenthesized receiver type: `fun (() -> R).name()`,
        // `fun <R> (suspend () -> R).name()`, `fun (A.() -> Unit)?.name()`.
        // The group is followed by `.` / `?.` (optionally after `?`), which
        // distinguishes it from a value-parameter list.
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
                stopsAtFunctionDelegation: true
            )
            // A block on the next line still belongs to a function whose
            // header has no expression body or explicit terminator.
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

    /// Returns the position after a parenthesized receiver and its `.` / `?.`.
    /// The caller can inspect that position to distinguish a named declaration
    /// from an anonymous function with a parenthesized extension receiver.
    func offsetAfterParenthesizedReceiver(from start: Int, maxDistance: Int? = nil) -> Int? {
        guard stream.peek(start).kind == .symbol(.lParen) else { return nil }
        var offset = offsetPastBalancedGroup(
            from: start, open: .symbol(.lParen), close: .symbol(.rParen), maxDistance: maxDistance
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
            // Destructuring declaration: val (a, b) = expr
            // Don't emit a missing-name diagnostic; the AST builder handles this pattern.
        } else if case .symbol(.lBracket) = stream.peek().kind {
            // Positional destructuring declaration (Kotlin 2.4): val [a, b] = expr
            // Don't emit a missing-name diagnostic; the AST builder handles this pattern.
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
                allowsPropertyDelegation: true
            )
            // In Kotlin, `get()`/`set()` accessors and explicit backing field
            // declarations on the next line are part of the property declaration.
            // After parseTail stops at a newline, absorb trailing accessor and
            // explicit field lines into dedicated CST nodes.
            while isPropertyAccessorStart(allowsBodyless: allowsBodylessAccessors)
                || isExplicitBackingFieldStart(stream.peek())
            {
                if isExplicitBackingFieldStart(stream.peek()) {
                    parseExplicitBackingField(into: &children, range: &range)
                } else {
                    parsePropertyAccessor(into: &children, range: &range)
                }
            }
        }

        return arena.appendNode(
            kind: .propertyDecl,
            range: range.value ?? invalidRange, children
        )
    }

    private func parsePropertyAccessor(into children: inout [SyntaxChild], range: inout RangeAccumulator) {
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
    }

    /// Reuses the `.propertyAccessor` kind so the AST builder can detect it
    /// via the leading `field` soft keyword.
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
        } else if parseEnumHeaderTail(into: &children, range: &range) {
        } else {
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

            if enumBodyStartsDeclaration() {
                children.append(.node(parseDeclaration()))
                continue
            }
            if !entryListEnded,
               isIdentifierLike(token.kind) || enumEntryStartsAfterLeadingAnnotations()
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

    /// Distinguishes a member declaration from an enum entry inside an enum body.
    /// Enum entry names are identifier-like and may be soft/modifier keywords
    /// (`data`, `value`, ...), so a modifier keyword only starts a declaration
    /// when another declaration token follows it.
    private func enumBodyStartsDeclaration() -> Bool {
        let kind = stream.peek().kind
        if kind == .keyword(.constructor) || kind == .softKeyword(.constructor) {
            return true
        }
        if kind == .symbol(.at) {
            // An annotation can prefix either an enum entry or a member
            // declaration. Look through the annotation before deciding which
            // parser should consume the node.
            return !enumEntryStartsAfterLeadingAnnotations()
        }
        if case .softKeyword(.context) = kind {
            return declarationPrefixVerdict(at: 0) == .declaration
        }
        guard case let .keyword(keyword) = kind, isDeclarationKeyword(keyword) else {
            return false
        }
        if Self.isDeclarationModifierKeyword(keyword) {
            return isDeclarationStart(stream.peek(1).kind)
        }
        return true
    }

    /// Mirrors the token shape consumed by `consumeDeclarationAnnotationPrefixIfPresent`
    /// without mutating the parser stream.
    private func enumEntryStartsAfterLeadingAnnotations() -> Bool {
        guard stream.peek().kind == .symbol(.at) else { return false }

        var offset = 0
        while stream.peek(offset).kind == .symbol(.at) {
            guard let end = offsetPastAnnotationPrefix(from: offset) else { return false }
            offset = end
        }

        let nextKind = stream.peek(offset).kind
        return isIdentifierLike(nextKind) && !isDeclarationStart(nextKind)
    }

    func parseEnumEntryDeclaration() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()

        while consumeDeclarationAnnotationPrefixIfPresent(into: &children, range: &range) {}
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
                    // A brace that belongs to a `by` delegate expression
                    // (`by when (x) { ... }`, `by object : C { }`, ...) is
                    // part of the header, not the enum body.
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

        var parenDepth = 0
        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof { break }
            if case .symbol(.rBrace) = token.kind, parenDepth == 0 { break }
            if case .symbol(.lBrace) = token.kind, parenDepth == 0 { break }
            if hasLeadingNewline(token), parenDepth == 0, !children.isEmpty, token.kind != .symbol(.colon), token.kind != .keyword(.this), token.kind != .keyword(.super) { break }
            if case .symbol(.semicolon) = token.kind, parenDepth == 0 {
                _ = consumeToken(into: &children, range: &range)
                break
            }
            _ = consumeToken(into: &children, range: &range)
            if case .symbol(.lParen) = token.kind { parenDepth += 1 }
            if case .symbol(.rParen) = token.kind { parenDepth = max(0, parenDepth - 1) }
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
        let next = stream.peek()
        let continuesHeaderAcrossNewline = includeBlock && (
            next.kind == .symbol(.colon)
                || next.kind == .symbol(.lessThan)
                || next.kind == .softKeyword(.where)
        ) || allowsClassHeaderColon && next.kind == .symbol(.lParen)
            || allowsClassDelegation && next.kind == .softKeyword(.by)
        // A body statement after a local class has no class-header role. Stop
        // before it so the block parser can keep the statement beside the class.
        let stopsAtNewline = hasLeadingNewline(next)
            && (includeBlock ? !continuesHeaderAcrossNewline : isDeclarationStart(next.kind))
        if stopsAtNewline {
            return
        }
        parseTail(
            inBlock: false, into: &children, range: &range,
            allowsClassHeaderColon: allowsClassHeaderColon,
            allowsClassDelegation: allowsClassDelegation,
            allowsWhereClauseContinuation: allowsWhereClauseContinuation,
            isClassBody: includeBlock
        )
        // Header scanning may stop at a newline after constructor parameters or
        // supertypes. The following brace still belongs to this declaration,
        // unless a terminator or an already parsed body has ended it.
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
