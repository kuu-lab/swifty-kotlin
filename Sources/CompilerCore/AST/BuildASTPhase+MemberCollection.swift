
extension BuildASTPhase {
    func declarationEnumEntries(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        diagnostics: DiagnosticEngine?
    ) -> [EnumEntryDecl] {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        // The parser keeps an enum entry and its anonymous class body as one
        // CST node. Walk those nodes directly so declaration keywords inside
        // the body (most importantly `override fun`) are not mistaken for a
        // class-level declaration and cause the whole entry to be discarded.
        let syntaxEntries = arena.children(of: bodyBlockID).compactMap { child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .enumEntry
            else {
                return nil
            }
            return childID
        }
        if !syntaxEntries.isEmpty {
            var entries: [EnumEntryDecl] = []
            entries.reserveCapacity(syntaxEntries.count)
            for entryNodeID in syntaxEntries {
                let tokens = collectTokens(from: entryNodeID, in: arena)
                var annotations: [AnnotationNode] = []
                var annotIndex = 0
                while annotIndex < tokens.count, tokens[annotIndex].kind == .symbol(.at) {
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: annotIndex, interner: interner, allowUseSiteTarget: false
                    ) {
                        if parsed.invalidUseSiteTargetRange == nil {
                            annotations.append(parsed.annotation)
                        }
                        annotIndex = parsed.nextIndex
                    } else {
                        annotIndex += 1
                    }
                }
                guard let nameIndex = tokens[annotIndex...].firstIndex(where: { token in
                    internedIdentifier(from: token, interner: interner) != nil
                }), let name = internedIdentifier(from: tokens[nameIndex], interner: interner) else {
                    continue
                }

                var constructorArgs: [CallArgument] = []
                if let argsNodeID = arena.children(of: entryNodeID).compactMap({ child -> NodeID? in
                    guard case let .node(childID) = child,
                          arena.node(childID).kind == .statement
                    else {
                        return nil
                    }
                    return childID
                }).first {
                    let argsTokens = collectTokens(from: argsNodeID, in: arena)
                    let afterParen = skipBalancedBracket(
                        in: argsTokens, from: 0, open: .symbol(.lParen), close: .symbol(.rParen)
                    )
                    let argTokens = Array(argsTokens[1..<afterParen])
                    let parser = ExpressionParser(
                        tokens: argTokens,
                        interner: interner,
                        astArena: astArena,
                        diagnostics: diagnostics
                    )
                    constructorArgs = parser.parseCallArguments()
                }

                let members = declarationMemberDecls(
                    from: entryNodeID, in: arena, interner: interner, astArena: astArena,
                    enumEntrySite: true
                )
                // Object declarations inside enum entries are prohibited on
                // JVM ("named object 'X' cannot be local" / "'companion' is
                // not applicable inside 'enum entry'"); EnumEntryDecl has no
                // object slots, so they are diagnosed here instead of being
                // silently dropped.
                for declID in members.nestedObjects {
                    guard case let .objectDecl(objectDecl) = astArena.decl(declID) else {
                        continue
                    }
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0429",
                        "named object '\(interner.resolve(objectDecl.name))' cannot be local. Try to use an anonymous object instead.",
                        range: objectDecl.range
                    )
                }
                for declID in [members.companionObject, members.companionBlockObject].compactMap({ $0 }) {
                    guard case let .objectDecl(companionDecl) = astArena.decl(declID) else {
                        continue
                    }
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0401",
                        "modifier 'companion' is not applicable inside 'enum entry'.",
                        range: companionDecl.range
                    )
                }
                entries.append(EnumEntryDecl(
                    range: arena.node(entryNodeID).range,
                    name: name,
                    annotations: annotations,
                    constructorArgs: constructorArgs,
                    initBlocks: declarationInitBlocks(
                        from: entryNodeID, in: arena, interner: interner, astArena: astArena
                    ),
                    classBodyInitOrder: declarationClassBodyInitOrder(
                        from: entryNodeID, in: arena, interner: interner
                    ),
                    memberFunctions: members.functions,
                    memberProperties: members.properties,
                    nestedClasses: members.nestedClasses
                ))
            }
            return entries
        }

        let tokens = collectTokens(from: bodyBlockID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        var seenOpeningBrace = false

        for token in tokens {
            if !seenOpeningBrace {
                if token.kind == .symbol(.lBrace) {
                    seenOpeningBrace = true
                }
                continue
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.rBrace)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                break
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.semicolon)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                break
            }

            if depth.isAtTopLevel,
               token.kind == .symbol(.comma)
            {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty {
            segments.append(current)
        }

        var entries: [EnumEntryDecl] = []
        entries.reserveCapacity(segments.count)
        for segment in segments {
            // Skip segments that contain declaration keywords — these are class member
            // declarations that appear in non-enum class bodies, not enum entries.
            let hasDeclKeyword = segment.contains(where: { token in
                switch token.kind {
                case .keyword(.val), .keyword(.var), .keyword(.fun),
                     .keyword(.class), .keyword(.object), .keyword(.interface),
                     .keyword(.typealias), .keyword(.constructor), .softKeyword(.constructor):
                    return true
                default:
                    return false
                }
            })
            if hasDeclKeyword { continue }

            var annotations: [AnnotationNode] = []
            var annotIndex = 0
            while annotIndex < segment.count, segment[annotIndex].kind == .symbol(.at) {
                if let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: segment, start: annotIndex, interner: interner, allowUseSiteTarget: false
                ) {
                    // Skip annotations that had an invalid (property) use-site target —
                    // those belong to property declarations, not enum entries.
                    if parsed.invalidUseSiteTargetRange == nil {
                        annotations.append(parsed.annotation)
                    }
                    annotIndex = parsed.nextIndex
                } else {
                    annotIndex += 1
                }
            }
            guard let nameIndex = segment[annotIndex...].firstIndex(where: { token in
                internedIdentifier(from: token, interner: interner) != nil
            }), let name = internedIdentifier(from: segment[nameIndex], interner: interner) else {
                continue
            }
            let nameToken = segment[nameIndex]
            var constructorArgs: [CallArgument] = []
            if let parenIndex = segment[nameIndex...].dropFirst().firstIndex(where: { $0.kind == .symbol(.lParen) }) {
                let afterParen = skipBalancedBracket(in: segment, from: parenIndex, open: .symbol(.lParen), close: .symbol(.rParen))
                let argTokens = Array(segment[(parenIndex + 1)..<afterParen])
                let parser = ExpressionParser(
                    tokens: argTokens,
                    interner: interner,
                    astArena: astArena,
                    diagnostics: diagnostics
                )
                constructorArgs = parser.parseCallArguments()
            }
            let end = segment.last?.range.end ?? nameToken.range.end
            entries.append(EnumEntryDecl(
                range: SourceRange(start: nameToken.range.start, end: end),
                name: name,
                annotations: annotations,
                constructorArgs: constructorArgs
            ))
        }
        return entries
    }

    func declarationNestedTypeAliases(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeAliasDecl] {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        var aliases: [TypeAliasDecl] = []
        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .typeAliasDecl
            else {
                continue
            }
            aliases.append(makeTypeAliasDecl(from: childID, in: arena, interner: interner, astArena: astArena))
        }
        return aliases
    }

    func declarationSuperTypeEntries(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [SuperTypeEntry] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return []
        }
        let declName = declarationName(from: nodeID, in: arena, interner: interner)
        let declarationKeyword: Keyword
        switch arena.node(nodeID).kind {
        case .classDecl:
            declarationKeyword = .class
        case .objectDecl:
            declarationKeyword = .object
        case .interfaceDecl:
            declarationKeyword = .interface
        default:
            return []
        }
        guard let introducerIndex = firstTopLevelKeywordIndex(in: tokens, matching: [declarationKeyword]),
              introducerIndex + 1 < tokens.count
        else {
            return []
        }
        // An unnamed `companion object : Supertype { ... }` has no identifier
        // between `object` and the supertype colon, so the supertype list starts
        // right after the introducer instead of after a name.
        let isUnnamedObject = declarationKeyword == .object
            && tokens[introducerIndex + 1].kind == .symbol(.colon)
        var index: Int
        if isUnnamedObject {
            index = introducerIndex + 1
        } else {
            guard let name = internedIdentifier(from: tokens[introducerIndex + 1], interner: interner),
                  name == declName
            else {
                return []
            }
            index = introducerIndex + 2
        }
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lessThan), close: .symbol(.greaterThan))
        index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
        // Primary constructors may use the explicit `constructor` keyword with
        // modifiers such as `actual`, a visibility modifier, and/or annotations.
        // Walk general modifiers here just as scanPrimaryConstructorHeader does.
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.at) {
                if let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                ) {
                    index = parsed.nextIndex
                    continue
                }
                break
            }
            if modifier(from: token) != nil {
                index += 1
                continue
            }
            break
        }
        if index < tokens.count,
           tokens[index].kind == .keyword(.constructor) || tokens[index].kind == .softKeyword(.constructor) {
            index += 1
            index = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
        }
        guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
            return []
        }
        let colonToken = tokens[index]
        index += 1

        var entries: [SuperTypeEntry] = []
        var current: [Token] = []
        var depth = BracketDepth()
        var delegateBraceTracker = DelegateExpressionBraceTracker()
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                if token.kind == .symbol(.lBrace) {
                    if delegateBraceTracker.braceContinuesDelegateExpression() {
                        // The brace belongs to the delegate expression
                        // (`by { ... }`, `by when (x) { ... }`, `by if (c)
                        // { } else { }`, `by object : C { }`, ...) and stays
                        // inside the supertype entry. A top-level brace the
                        // delegate expression cannot contain is the
                        // declaration body and stays outside the entry.
                        delegateBraceTracker.note(token.kind, atTopLevel: true)
                        current.append(token)
                        depth.track(token.kind)
                        index += 1
                        continue
                    }
                    break
                }
                if token.kind == .symbol(.semicolon) {
                    break
                }
                if case .softKeyword(.where) = token.kind {
                    break
                }
                if token.kind == .symbol(.comma), delegateBraceTracker.commaEndsSupertypeEntry {
                    if let entry = parseSuperTypeEntry(from: current, interner: interner, astArena: astArena) {
                        entries.append(entry)
                    } else {
                        diagnostics?.error(
                            "KSWIFTK-PARSE-0020",
                            "Expected type after ':'.",
                            range: current.first?.range ?? token.range
                        )
                    }
                    current.removeAll(keepingCapacity: true)
                    delegateBraceTracker.reset()
                    index += 1
                    continue
                }
            }

            delegateBraceTracker.note(token.kind, atTopLevel: depth.isAtTopLevel)
            depth.track(token.kind)
            current.append(token)
            index += 1
        }
        if let entry = parseSuperTypeEntry(from: current, interner: interner, astArena: astArena) {
            entries.append(entry)
        } else {
            let following = index < tokens.count ? tokens[index] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: current.first?.range ?? following?.range ?? colonToken.range
            )
        }
        return entries
    }

    private func parseSuperTypeEntry(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> SuperTypeEntry? {
        guard !tokens.isEmpty else { return nil }

        var byIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                byIndex = index
                break
            }
            depth.track(token.kind)
        }

        let typeTokens: [Token]
        let exprTokens: [Token]
        if let byIndex {
            typeTokens = Array(tokens[..<byIndex])
            // Remove only entry-level semicolons; semicolons inside delegate
            // bodies (`by when (x) { 1 -> f(); g() ... }`) are part of the
            // expression's own statements and must remain available.
            exprTokens = filterTopLevelSemicolons(tokens[(byIndex + 1)...])
        } else {
            typeTokens = tokens
            exprTokens = []
        }

        guard let parsedSuperType = parseSuperTypeTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            return nil
        }

        let delegateExpr: ExprID?
        if exprTokens.isEmpty {
            delegateExpr = nil
        } else {
            let parser = ExpressionParser(
                tokens: exprTokens, interner: interner, astArena: astArena, diagnostics: diagnostics
            )
            delegateExpr = parser.parse()
        }

        return SuperTypeEntry(
            typeRef: parsedSuperType.ref,
            delegateExpression: delegateExpr,
            constructorArgs: parsedSuperType.constructorArgs,
            hasConstructorCallSyntax: parsedSuperType.hasConstructorCallSyntax,
            range: parsedSuperType.range
        )
    }

    func declarationSuperTypes(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [TypeRefID] {
        let entries = declarationSuperTypeEntries(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return entries.map(\.typeRef)
    }

    private struct ParsedSuperType {
        let ref: TypeRefID
        let constructorArgs: [CallArgument]
        let hasConstructorCallSyntax: Bool
        let range: SourceRange?
    }

    private func parseSuperTypeTypeRef(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ParsedSuperType? {
        guard !tokens.isEmpty else { return nil }

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

        let typeEndIndex = max(parsed.consumed - 1, 0)
        let range = SourceRange(start: tokens[0].range.start, end: tokens[typeEndIndex].range.end)
        let remainingStart = parsed.consumed
        guard remainingStart < tokens.count else {
            return ParsedSuperType(
                ref: parsed.ref,
                constructorArgs: [],
                hasConstructorCallSyntax: false,
                range: range
            )
        }

        guard tokens[remainingStart].kind == .symbol(.lParen) else {
            return nil
        }

        var parenDepth = 0
        var index = remainingStart
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                parenDepth += 1
            } else if kind == .symbol(.rParen) {
                parenDepth -= 1
                if parenDepth == 0 {
                    index += 1
                    break
                }
            }
            index += 1
        }

        guard parenDepth == 0 else { return nil }
        let trailing = tokens[index...]
        guard trailing.allSatisfy({ $0.kind == .symbol(.semicolon) }) else { return nil }

        let args = parseSuperTypeConstructorArgs(
            Array(tokens[(remainingStart + 1) ..< (index - 1)]),
            interner: interner,
            astArena: astArena
        )
        return ParsedSuperType(
            ref: parsed.ref,
            constructorArgs: args,
            hasConstructorCallSyntax: true,
            range: range
        )
    }

    private func parseSuperTypeConstructorArgs(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> [CallArgument] {
        var args: [CallArgument] = []
        var current: [Token] = []
        var depth = BracketDepth()
        // Object-expression supertype lists contain top-level commas before the body.
        var isParsingObjectLiteralHeader = false

        func flush() {
            guard !current.isEmpty else { return }
            let parser = ExpressionParser(
                tokens: current, interner: interner, astArena: astArena, diagnostics: diagnostics
            )
            // Parse as a call argument (not a bare expression) so `name = value`
            // labels and `*spread` survive; otherwise `Base(y = 1, x = 2)`
            // degrades to positional assignment expressions.
            if let argument = parser.parseCallArgument() {
                args.append(argument)
                if let unexpected = parser.current() {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0015",
                        "Expected ',' or ')' after call argument.",
                        range: unexpected.range
                    )
                }
            } else {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0022",
                    "Expected an argument.",
                    range: current.last?.range
                )
            }
            current.removeAll(keepingCapacity: true)
        }

        for token in tokens {
            if depth.isAtTopLevel, token.kind == .keyword(.object) {
                isParsingObjectLiteralHeader = true
            }
            if token.kind == .symbol(.comma), depth.isAtTopLevel, !isParsingObjectLiteralHeader {
                // An empty slot before the comma (`Base(,1)`, `Base(1,,2)`,
                // `Base(,)`) is not a legal argument — only a trailing comma
                // after a real argument is allowed (Kotlin 1.4+).
                if current.isEmpty {
                    diagnostics?.error(
                        "KSWIFTK-PARSE-0022",
                        "Expected an argument.",
                        range: token.range
                    )
                } else {
                    flush()
                }
                continue
            }
            if token.kind == .symbol(.lBrace), depth.isAtTopLevel, isParsingObjectLiteralHeader {
                isParsingObjectLiteralHeader = false
            }
            depth.track(token.kind)
            current.append(token)
        }
        flush()
        return args
    }

    func declarationMemberDecls(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        enumEntrySite: Bool = false
    ) -> (functions: [DeclID], properties: [DeclID], nestedClasses: [DeclID], nestedObjects: [DeclID], companionObject: DeclID?, companionBlockObject: DeclID?) {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return ([], [], [], [], nil, nil)
        }

        var functions: [DeclID] = []
        var properties: [DeclID] = []
        var nestedClasses: [DeclID] = []
        var nestedObjects: [DeclID] = []
        var companionObject: DeclID?
        var companionBlockObject: DeclID?
        var companionBlockFunctions: [DeclID] = []
        var companionBlockProperties: [DeclID] = []
        var companionBlockRange: SourceRange?
        var pendingMemberAnnotations: [AnnotationNode] = []
        var pendingMemberContextReceivers: [ContextReceiverDecl] = []

        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child else {
                pendingMemberAnnotations = []
                pendingMemberContextReceivers = []
                continue
            }
            if arena.node(childID).kind == .statement {
                let tokens = collectTokens(from: childID, in: arena)
                if tokens.first?.kind == .keyword(.companion),
                   let blockNodeID = arena.children(of: childID).compactMap({ child -> NodeID? in
                       guard case let .node(blockID) = child,
                             arena.node(blockID).kind == .block
                       else {
                           return nil
                       }
                       return blockID
                   }).first
                {
                    companionBlockRange = companionBlockRange ?? arena.node(blockNodeID).range
                    var blockAnnotations: [AnnotationNode] = []
                    var blockContextReceivers: [ContextReceiverDecl] = []
                    for blockChild in arena.children(of: blockNodeID) {
                        guard case let .node(blockMemberID) = blockChild else {
                            blockAnnotations = []
                            blockContextReceivers = []
                            continue
                        }
                        let blockMemberKind = arena.node(blockMemberID).kind
                        if blockMemberKind == .statement {
                            let blockMemberTokens = collectTokens(from: blockMemberID, in: arena)
                            let parsedContextReceivers = parseContextReceivers(
                                from: blockMemberTokens, interner: interner, astArena: astArena
                            )
                            if !parsedContextReceivers.isEmpty {
                                blockContextReceivers = parsedContextReceivers
                            } else if blockMemberTokens.first?.kind != .symbol(.at) {
                                blockContextReceivers = []
                            }
                            if let annotations = declarationPrefixAnnotations(
                                from: blockMemberID, in: arena, interner: interner
                            ) {
                                blockAnnotations = annotations
                            } else if parsedContextReceivers.isEmpty, blockMemberTokens.first?.kind != .symbol(.at) {
                                blockAnnotations = []
                            }
                            continue
                        }

                        var blockNestedClasses: [DeclID] = []
                        var blockNestedObjects: [DeclID] = []
                        var blockCompanionObject: DeclID?
                        processMemberChild(
                            blockMemberID,
                            in: arena,
                            interner: interner,
                            astArena: astArena,
                            prefixedAnnotations: blockAnnotations,
                            prefixedContextReceivers: blockContextReceivers,
                            functions: &companionBlockFunctions,
                            properties: &companionBlockProperties,
                            nestedClasses: &blockNestedClasses,
                            nestedObjects: &blockNestedObjects,
                            companionObject: &blockCompanionObject
                        )
                        blockAnnotations = []
                        blockContextReceivers = []
                    }
                    pendingMemberAnnotations = []
                    pendingMemberContextReceivers = []
                    continue
                }
                let parsedContextReceivers = parseContextReceivers(
                    from: tokens, interner: interner, astArena: astArena
                )
                if !parsedContextReceivers.isEmpty {
                    pendingMemberContextReceivers = parsedContextReceivers
                } else if tokens.first?.kind != .symbol(.at) {
                    pendingMemberContextReceivers = []
                }
                if let annotations = declarationPrefixAnnotations(
                    from: childID, in: arena, interner: interner
                ) {
                    pendingMemberAnnotations = annotations
                } else if parsedContextReceivers.isEmpty, tokens.first?.kind != .symbol(.at) {
                    pendingMemberAnnotations = []
                }
                continue
            }
            let prefixedAnnotations = pendingMemberAnnotations
            let prefixedContextReceivers = pendingMemberContextReceivers
            pendingMemberAnnotations = []
            pendingMemberContextReceivers = []
            processMemberChild(
                childID,
                in: arena, interner: interner, astArena: astArena,
                prefixedAnnotations: prefixedAnnotations,
                prefixedContextReceivers: prefixedContextReceivers,
                functions: &functions, properties: &properties,
                nestedClasses: &nestedClasses, nestedObjects: &nestedObjects,
                companionObject: &companionObject,
                enumEntrySite: enumEntrySite
            )
        }

        if let companionBlockRange {
            let blockObject = ObjectDecl(
                range: companionBlockRange,
                // Companion blocks have no source-visible companion object.
                // Keep their implementation scope as a hidden nested object so
                // it cannot be referenced as `C.Companion` or reflected as one.
                name: interner.intern("$CompanionBlocks"),
                modifiers: [],
                classBodyInitOrder: companionBlockProperties.indices.map { .property($0) },
                memberFunctions: companionBlockFunctions,
                memberProperties: companionBlockProperties
            )
            let blockObjectID = astArena.appendDecl(.objectDecl(blockObject))
            nestedObjects.append(blockObjectID)
            companionBlockObject = blockObjectID
        }

        return (functions, properties, nestedClasses, nestedObjects, companionObject, companionBlockObject)
    }

    private func declarationPrefixAnnotations(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner
    ) -> [AnnotationNode]? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard !tokens.isEmpty else {
            return nil
        }

        var annotations: [AnnotationNode] = []
        var sawModifier = false
        var index = 0
        while index < tokens.count {
            if tokens[index].kind == .symbol(.at),
               let parsed = AnnotationParsingSupport.parseAnnotation(
                   from: tokens, start: index, interner: interner, allowUseSiteTarget: true
               )
            {
                annotations.append(parsed.annotation)
                index = parsed.nextIndex
                continue
            }
            guard modifier(from: tokens[index]) != nil else {
                return nil
            }
            sawModifier = true
            index += 1
        }

        guard sawModifier, !annotations.isEmpty else {
            return nil
        }
        return annotations
    }

    private func processMemberChild(
        _ childID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena,
        prefixedAnnotations: [AnnotationNode],
        prefixedContextReceivers: [ContextReceiverDecl],
        functions: inout [DeclID],
        properties: inout [DeclID],
        nestedClasses: inout [DeclID],
        nestedObjects: inout [DeclID],
        companionObject: inout DeclID?,
        enumEntrySite: Bool = false
    ) {
        let childNode = arena.node(childID)
        switch childNode.kind {
        case .funDecl:
            let funDecl = makeFunDecl(
                from: childID, in: arena, interner: interner,
                astArena: astArena, prefixedAnnotations: prefixedAnnotations,
                prefixedContextReceivers: prefixedContextReceivers
            )
            functions.append(astArena.appendDecl(.funDecl(funDecl)))
        case .propertyDecl:
            let propDecl = makePropertyDecl(
                from: childID, in: arena, interner: interner, astArena: astArena,
                prefixedContextReceivers: prefixedContextReceivers
            )
            properties.append(astArena.appendDecl(.propertyDecl(propDecl)))
        case .classDecl:
            let classDecl = makeClassDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            // kotlinc rejects named nominal declarations inside enum entry
            // bodies: classes/interfaces outright, enum classes via the
            // modifier check, annotation classes as both local and prohibited.
            if enumEntrySite {
                if classDecl.modifiers.contains(.enumModifier) {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0400",
                        "modifier 'enum' is not applicable to 'local class'.",
                        range: classDecl.range
                    )
                } else if classDecl.modifiers.contains(.annotationClass) {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0429",
                        "annotation class cannot be local.",
                        range: classDecl.range
                    )
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0451",
                        "'Annotation class' is prohibited here.",
                        range: classDecl.range
                    )
                } else {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0451",
                        "'Class' is prohibited here.",
                        range: classDecl.range
                    )
                }
            } else {
                nestedClasses.append(astArena.appendDecl(.classDecl(classDecl)))
            }
        case .interfaceDecl:
            let interfaceDecl = makeInterfaceDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            if enumEntrySite {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0451",
                    "'Interface' is prohibited here.",
                    range: interfaceDecl.range
                )
            } else {
                nestedClasses.append(astArena.appendDecl(.interfaceDecl(interfaceDecl)))
            }
        case .objectDecl:
            let objectDecl = makeObjectDecl(from: childID, in: arena, interner: interner, astArena: astArena)
            let declID = astArena.appendDecl(.objectDecl(objectDecl))
            if enumEntrySite {
                // Enum entry bodies admit no named objects at all; companions
                // report the modifier error instead and are not counted.
                if objectDecl.modifiers.contains(.companion) {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0401",
                        "modifier 'companion' is not applicable inside 'enum entry'.",
                        range: objectDecl.range
                    )
                } else {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0429",
                        "named object '\(interner.resolve(objectDecl.name))' cannot be local. Try to use an anonymous object instead.",
                        range: objectDecl.range
                    )
                }
            } else if objectDecl.modifiers.contains(.companion) {
                if companionObject == nil {
                    companionObject = declID
                } else {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0435",
                        "A declaration can have only one companion object.",
                        range: objectDecl.range
                    )
                    // Keep the duplicate in the tree as a nested object so
                    // member references still resolve and its members are
                    // analyzed, like kotlinc — which also reports it under
                    // `companion`-modifier site checks where applicable.
                    nestedObjects.append(declID)
                }
            } else {
                nestedObjects.append(declID)
            }
        default:
            break
        }
    }

    /// `ClassDecl.memberProperties` is `constructorProperties + members.properties`
    /// (primary-constructor `val`/`var` params first, then body-declared
    /// properties — see `makeClassDecl`), so `propertyIndex` must start at
    /// `constructorPropertyCount` rather than 0. Otherwise the `.property(i)`
    /// entries this function emits — which are indexed relative to the body
    /// block alone — end up pointing at the wrong `memberProperties` entry
    /// (or a constructor-parameter property with no body initializer) as soon
    /// as the class has both kinds of property, and body property initializers
    /// silently stop running. `ObjectDecl.memberProperties` has no constructor
    /// properties prepended, so its callers pass 0 (the default).
    func declarationClassBodyInitOrder(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner _: StringInterner,
        constructorPropertyCount: Int = 0
    ) -> [ClassBodyInitMember] {
        guard let bodyBlockID = arena.children(of: nodeID).compactMap({ child -> NodeID? in
            guard case let .node(childID) = child,
                  arena.node(childID).kind == .block
            else {
                return nil
            }
            return childID
        }).first else {
            return []
        }

        var order: [ClassBodyInitMember] = []
        var propertyIndex = constructorPropertyCount
        var initBlockIndex = 0

        for child in arena.children(of: bodyBlockID) {
            guard case let .node(childID) = child else {
                continue
            }
            let childNode = arena.node(childID)

            if childNode.kind == .propertyDecl {
                order.append(.property(propertyIndex))
                propertyIndex += 1
                continue
            }

            // Init blocks appear as statement-like nodes whose first direct
            // token is the `init` soft keyword (same logic used by
            // `declarationInitBlocks`).
            if isStatementLikeKind(childNode.kind) {
                let headerTokens = collectDirectTokens(from: childID, in: arena).filter { token in
                    token.kind != .symbol(.semicolon)
                }
                if let firstToken = headerTokens.first {
                    if firstToken.kind == .softKeyword(.`init`) {
                        order.append(.initBlock(initBlockIndex))
                        initBlockIndex += 1
                    }
                }
            }
        }
        return order
    }

    func declarationDelegateExpression(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        // A delegate expression follows the same call grammar as any other
        // initializer.  In particular, a trailing lambda is the final call
        // argument and must participate in overload resolution and inference.
        let tokens = propertyHeadTokens(
            from: nodeID,
            in: arena,
            includingTrailingLambdaTokens: true
        )
        guard !tokens.isEmpty else {
            return nil
        }

        var byIndex: Int?
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            // Once the initializer starts, any `by` belongs to that expression,
            // not to the property declaration.
            if token.kind == .symbol(.assign), depth.isAtTopLevel {
                return nil
            }
            if case .softKeyword(.by) = token.kind, depth.isAtTopLevel {
                byIndex = index
                break
            }
            depth.track(token.kind)
        }
        guard let byIndex else {
            return nil
        }
        let start = byIndex + 1
        guard start < tokens.count else {
            return nil
        }
        // Remove only declaration-level semicolons; semicolons
        // in the lambda body must remain available to the block parser.
        let exprTokens = filterTopLevelSemicolons(tokens[start...])
        guard !exprTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(
            tokens: ArraySlice(exprTokens), interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        return parser.parse()
    }
}
