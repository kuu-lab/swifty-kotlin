
extension BuildASTPhase {
    /// Returns the index of the `class` keyword that introduces a class declaration,
    /// skipping `class` tokens inside annotation arguments, type arguments, or
    /// `Foo::class` class-literal expressions that appear before the declaration.
    private func classDeclarationKeywordIndex(in tokens: [Token]) -> Int? {
        var depth = BracketDepth()
        var previousToken: Token?
        for (index, token) in tokens.enumerated() {
            if depth.isAtTopLevel,
               case .keyword(.class) = token.kind,
               let previous = previousToken,
               previous.kind == .symbol(.doubleColon) {
                previousToken = token
                continue
            }
            if depth.isAtTopLevel, case .keyword(.class) = token.kind {
                return index
            }
            depth.track(token.kind)
            previousToken = token
        }
        return nil
    }
    func makeClassDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ClassDecl {
        let node = arena.node(nodeID)
        let primaryConstructorParams = declarationValueParameters(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let constructorProperties = primaryConstructorPropertyDecls(
            from: primaryConstructorParams,
            classRange: node.range,
            astArena: astArena
        )
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return ClassDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            isInner: modifiers.contains(.inner),
            typeParams: typeParams,
            primaryConstructorParams: primaryConstructorParams,
            primaryConstructorModifiers: declarationPrimaryConstructorModifiers(from: nodeID, in: arena, interner: interner),
            primaryConstructorAnnotations: declarationPrimaryConstructorAnnotations(from: nodeID, in: arena, interner: interner),
            hasPrimaryConstructorSyntax: declarationHasPrimaryConstructorSyntax(from: nodeID, in: arena),
            superTypeEntries: declarationSuperTypeEntries(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            enumEntries: declarationEnumEntries(from: nodeID, in: arena, interner: interner, astArena: astArena, diagnostics: diagnostics),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            classBodyInitOrder: declarationClassBodyInitOrder(
                from: nodeID, in: arena, interner: interner,
                constructorPropertyCount: constructorProperties.count
            ),
            secondaryConstructors: declarationSecondaryConstructors(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: constructorProperties + members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects,
            companionObject: members.companionObject
        )
    }

    /// Extracts annotations placed on the primary constructor in a class header,
    /// e.g. `class Foo @Inject constructor()`.
    func declarationPrimaryConstructorAnnotations(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> [AnnotationNode] {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return []
        }
        var index = classIndex + 1
        var sawClassName = false
        var depth = BracketDepth()
        var annotations: [AnnotationNode] = []
        while index < tokens.count {
            let token = tokens[index]
            if !sawClassName {
                if case .identifier = token.kind {
                    sawClassName = true
                } else if case .backtickedIdentifier = token.kind {
                    sawClassName = true
                }
                index += 1
                continue
            }
            if depth.isAtTopLevel {
                switch token.kind {
                case .keyword(.constructor), .softKeyword(.constructor),
                     .symbol(.lParen), .symbol(.colon), .symbol(.lBrace):
                    return annotations
                case .symbol(.at):
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                    ) {
                        annotations.append(parsed.annotation)
                        index = parsed.nextIndex
                    } else {
                        index += 1
                    }
                    continue
                default:
                    break
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return annotations
    }

    /// Extracts modifiers attached to the primary constructor declaration in a
    /// class header, e.g. `class Foo private constructor()`.
    func declarationPrimaryConstructorModifiers(
        from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner
    ) -> Modifiers {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return []
        }
        var index = classIndex + 1
        var sawClassName = false
        var depth = BracketDepth()
        var constructorModifiers: Modifiers = []
        while index < tokens.count {
            let token = tokens[index]
            if !sawClassName {
                if case .identifier = token.kind {
                    sawClassName = true
                } else if case .backtickedIdentifier = token.kind {
                    sawClassName = true
                }
                index += 1
                continue
            }
            if depth.isAtTopLevel {
                switch token.kind {
                case .keyword(.constructor), .softKeyword(.constructor):
                    return constructorModifiers
                case .symbol(.lParen), .symbol(.colon), .symbol(.lBrace):
                    return []
                case .symbol(.at):
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                    ) {
                        index = parsed.nextIndex
                    } else {
                        index += 1
                    }
                    continue
                default:
                    break
                }
                if let modifier = modifier(from: token) {
                    constructorModifiers.insert(modifier)
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return []
    }

    /// Detects whether the class header contains explicit constructor parentheses,
    /// distinguishing `class Foo()` from `class Foo`.
    ///
    /// This uses token-level scanning because the CST does not distinguish
    /// "no primary constructor" from "primary constructor with zero parameters";
    /// both produce an empty `primaryConstructorParams` array. The function
    /// scans tokens after the `class` keyword, skipping type-parameter angle
    /// brackets (`<…>`), and returns `true` if it encounters `(` before `:` or `{`.
    ///
    /// Examples:
    /// - `class Foo()` → `true`
    /// - `class Foo`   → `false`
    /// - `class Foo<T>()` → `true`
    /// - `class Foo<T>` → `false`
    /// - `class Foo : Bar` → `false`
    ///
    /// Limitation: nested generic bounds (e.g. `class Foo<T: List<Int>>()`) use
    /// `<` and `>` tokens that are tracked via depth counting; the lexer does not
    /// emit `>>` as a single token, so this is handled correctly.
    func declarationHasPrimaryConstructorSyntax(from nodeID: NodeID, in arena: SyntaxArena) -> Bool {
        let tokens = collectTokens(from: nodeID, in: arena)
        // Skip past the class keyword and name (and optional type params in `<>`).
        // A `(` before any `:` or `{` indicates primary constructor syntax.
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return false
        }
        var depth = BracketDepth()
        var index = classIndex + 1
        if index < tokens.count, TypeRefParserCore.isTypeLikeNameToken(tokens[index].kind) {
            index += 1
        }
        if index < tokens.count, tokens[index].kind == .symbol(.lessThan) {
            index = skipBalancedBracket(
                in: tokens,
                from: index,
                open: .symbol(.lessThan),
                close: .symbol(.greaterThan)
            )
        }
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                if case .symbol(.lParen) = token.kind {
                    return true
                }
                if token.kind == .symbol(.colon) || token.kind == .symbol(.lBrace) {
                    return false
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return false
    }

    func makeInterfaceDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> InterfaceDecl {
        let node = arena.node(nodeID)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return InterfaceDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            isFunInterface: modifiers.contains(.funModifier),
            typeParams: typeParams,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects,
            companionObject: members.companionObject
        )
    }

    func makeObjectDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> ObjectDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        let members = declarationMemberDecls(from: nodeID, in: arena, interner: interner, astArena: astArena)
        return ObjectDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: modifiers,
            annotations: annotations,
            superTypes: declarationSuperTypes(from: nodeID, in: arena, interner: interner, astArena: astArena),
            nestedTypeAliases: declarationNestedTypeAliases(from: nodeID, in: arena, interner: interner, astArena: astArena),
            initBlocks: declarationInitBlocks(from: nodeID, in: arena, interner: interner, astArena: astArena),
            classBodyInitOrder: declarationClassBodyInitOrder(from: nodeID, in: arena, interner: interner),
            memberFunctions: members.functions,
            memberProperties: members.properties,
            nestedClasses: members.nestedClasses,
            nestedObjects: members.nestedObjects
        )
    }

    func makeFunDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> FunDecl {
        let node = arena.node(nodeID)
        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let isSuspend = modifiers.contains(.suspend)
        let isInline = modifiers.contains(.inline)
        let isTailrec = modifiers.contains(.tailrec)
        let functionName = declarationFunctionName(from: nodeID, in: arena, interner: interner)
        let valueParams = declarationValueParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let explicitReceiverType = declarationReceiverType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let contextReceiverTypes = declarationContextReceiverTypes(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        )
        let receiverType = explicitReceiverType ?? contextReceiverTypes.first
        let returnType = declarationReturnType(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let body = declarationBody(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        return FunDecl(
            range: node.range,
            name: functionName,
            modifiers: modifiers,
            annotations: annotations,
            typeParams: typeParams,
            receiverType: receiverType,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            isInline: isInline,
            isTailrec: isTailrec
        )
    }

    func makePropertyDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> PropertyDecl {
        let node = arena.node(nodeID)
        let accessors = declarationPropertyAccessors(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let delegateExpr = declarationDelegateExpression(from: nodeID, in: arena, interner: interner, astArena: astArena)

        // When a delegate expression exists, the trailing lambda body (e.g. `lazy { body }`)
        // is a block child of the property node that `propertyHeadTokens` excludes.
        // Extract it here so KIR lowering can create the lambda function from it.
        var delegateBody: FunctionBody?
        var delegateBodyParams: [InternedString] = []
        if delegateExpr != nil {
            // Find the block child node — this is the trailing lambda body.
            for child in arena.children(of: nodeID) {
                if case let .node(childID) = child, arena.node(childID).kind == .block {
                    // A parameterized trailing lambda (`{ prop, old, new -> ... }`)
                    // cannot be recovered from the CST statement nodes: the
                    // parameter list and the arrow form their own statement node
                    // that the block-statement parser cannot make sense of. Re-parse
                    // the block's tokens as a lambda literal so both the parameter
                    // names and the real body statements survive.
                    if let parsed = delegateLambdaFromBlockTokens(
                        blockNodeID: childID, in: arena, interner: interner, astArena: astArena
                    ) {
                        delegateBodyParams = parsed.params
                        delegateBody = parsed.body
                        break
                    }
                    let exprs = blockExpressions(from: childID, in: arena, interner: interner, astArena: astArena)
                    delegateBody = .block(exprs, arena.node(childID).range)
                    break
                }
            }
        }

        let modifiers = declarationModifiers(from: nodeID, in: arena)
        let annotations = declarationAnnotations(from: nodeID, in: arena, interner: interner)
        let receiverType = declarationPropertyReceiverType(
            from: nodeID, in: arena, interner: interner, astArena: astArena
        )
        let propertyName: InternedString = if receiverType != nil {
            declarationPropertyNameAfterDot(from: nodeID, in: arena, interner: interner)
        } else {
            declarationPropertyName(from: nodeID, in: arena, interner: interner)
        }

        // Kotlin 2.0 explicit backing field: `field = expr` or `field: Type = expr`
        let explicitField = declarationExplicitBackingField(
            from: nodeID, in: arena, interner: interner, astArena: astArena
        )

        return PropertyDecl(
            range: node.range,
            name: propertyName,
            modifiers: modifiers,
            annotations: annotations,
            type: declarationPropertyType(from: nodeID, in: arena, interner: interner, astArena: astArena),
            isVar: declarationIsVar(from: nodeID, in: arena),
            initializer: declarationPropertyInitializer(from: nodeID, in: arena, interner: interner, astArena: astArena),
            getter: accessors.getter,
            setter: accessors.setter,
            delegateExpression: delegateExpr,
            delegateBody: delegateBody,
            delegateBodyParams: delegateBodyParams,
            receiverType: receiverType,
            explicitBackingField: explicitField
        )
    }

    /// Re-parses a delegate property's trailing-lambda block from its tokens so
    /// that a declared parameter list (`{ prop, old, new -> ... }`) is preserved.
    /// Returns `nil` for parameterless lambdas, which the CST statement nodes
    /// already describe correctly.
    private func delegateLambdaFromBlockTokens(
        blockNodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (params: [InternedString], body: FunctionBody)? {
        let tokens = collectTokens(from: blockNodeID, in: arena)
        guard let last = tokens.last,
              tokens.contains(where: { $0.kind == .symbol(.arrow) })
        else {
            return nil
        }
        let eofRange = SourceRange(start: last.range.end, end: last.range.end)
        let parser = ExpressionParser(
            tokens: (tokens + [Token(kind: .eof, range: eofRange)])[...],
            interner: interner,
            astArena: astArena
        )
        guard let lambdaExprID = parser.parseLambdaLiteral(),
              let lambdaExpr = astArena.expr(lambdaExprID),
              case let .lambdaLiteral(params, bodyExprID, _, _) = lambdaExpr,
              !params.isEmpty,
              let bodyExpr = astArena.expr(bodyExprID)
        else {
            return nil
        }
        if case let .blockExpr(statements, trailingExpr, range) = bodyExpr {
            var exprs = statements
            if let trailingExpr {
                exprs.append(trailingExpr)
            }
            return (params, .block(exprs, range))
        }
        guard let range = astArena.exprRange(bodyExprID) else {
            return nil
        }
        return (params, .expr(bodyExprID, range))
    }

    func makeTypeAliasDecl(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner, astArena: ASTArena) -> TypeAliasDecl {
        let node = arena.node(nodeID)
        let rawTypeParams = declarationTypeParameters(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let whereClauses = declarationWhereClauses(from: nodeID, in: arena, interner: interner, astArena: astArena)
        let typeParams = applyWhereClauses(rawTypeParams, whereClauses: whereClauses)
        return TypeAliasDecl(
            range: node.range,
            name: declarationName(from: nodeID, in: arena, interner: interner),
            modifiers: declarationModifiers(from: nodeID, in: arena),
            annotations: declarationAnnotations(from: nodeID, in: arena, interner: interner),
            typeParams: typeParams,
            underlyingType: declarationTypeAliasRHS(from: nodeID, in: arena, interner: interner, astArena: astArena)
        )
    }

    func declarationTypeAliasRHS(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let assignIndex = tokens.firstIndex(where: { $0.kind == .symbol(.assign) }) else {
            return nil
        }
        let rhsTokens = Array(tokens[(assignIndex + 1)...]).filter { $0.kind != .symbol(.semicolon) }
        return parseTypeRef(from: rhsTokens, interner: interner, astArena: astArena)
    }

    func declarationName(from nodeID: NodeID, in arena: SyntaxArena, interner: StringInterner) -> InternedString {
        let tokens = collectTokens(from: nodeID, in: arena)
        if let introducerIndex = declarationIntroducerIndex(in: tokens) {
            var index = introducerIndex + 1
            if tokens[introducerIndex].kind == .keyword(.enum),
               index < tokens.count,
               tokens[index].kind == .keyword(.class)
            {
                index += 1
            }
            if tokens[introducerIndex].kind == .keyword(.fun),
               index < tokens.count,
               tokens[index].kind == .symbol(.lessThan)
            {
                index = skipBalancedBracket(
                    in: tokens,
                    from: index,
                    open: .symbol(.lessThan),
                    close: .symbol(.greaterThan)
                )
            }
            while index < tokens.count {
                let token = tokens[index]
                if token.kind == .symbol(.lParen)
                    || token.kind == .symbol(.lBrace)
                    || token.kind == .symbol(.colon)
                    || token.kind == .symbol(.assign)
                    || token.kind == .symbol(.semicolon)
                {
                    break
                }
                if let name = internedIdentifier(from: token, interner: interner) {
                    if case let .keyword(keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                        index += 1
                        continue
                    }
                    return name
                }
                index += 1
            }
            return interner.intern("")
        }

        for token in tokens {
            if let name = internedIdentifier(from: token, interner: interner) {
                if case let .keyword(keyword) = token.kind, isLeadingDeclarationKeyword(keyword) {
                    continue
                }
                return name
            }
        }
        return interner.intern("")
    }

    func declarationValueParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ValueParamDecl] {
        let tokens = collectTokens(from: nodeID, in: arena)
        let nodeKind = arena.node(nodeID).kind
        // Only look for the opening `(` that occurs before any `{` (class body).
        // This prevents picking up `(` from member function declarations like
        // `class F { operator fun invoke(x: Int) }` as constructor parameters.
        guard let startIndex = declarationParameterOpenParenIndex(in: tokens, nodeKind: nodeKind, interner: interner) else {
            return []
        }

        var depth = BracketDepth()
        var arguments: [ValueParamDecl] = []
        var paramTokens: [Token] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.rParen), depth.paren == 0 {
                break
            }
            depth.track(token.kind)
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                if token.kind == .symbol(.lBrace) {
                    // Stop at block start for simple tail-recognition in function declarations.
                    break
                }
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &arguments, interner: interner, astArena: astArena)
        }
        return arguments
    }

    func declarationIntroducerIndex(in tokens: [Token]) -> Int? {
        var depth = BracketDepth()
        var previousToken: Token?
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            defer { previousToken = token }
            guard depth.isAtTopLevel else { continue }
            guard case let .keyword(keyword) = token.kind else { continue }
            if keyword == .class,
               let previous = previousToken,
               previous.kind == .symbol(.doubleColon) {
                continue
            }
            switch keyword {
            case .class, .object, .interface, .fun, .val, .var, .typealias, .enum, .package, .import:
                return index
            case .companion:
                if index + 1 < tokens.count, tokens[index + 1].kind == .keyword(.object) {
                    return index + 1
                }
            default:
                continue
            }
        }
        return nil
    }

    func declarationParameterOpenParenIndex(
        in tokens: [Token],
        nodeKind: SyntaxKind,
        interner: StringInterner
    ) -> Int? {
        switch nodeKind {
        case .funDecl:
            functionParameterOpenParenIndex(in: tokens)
        case .classDecl:
            classPrimaryConstructorOpenParenIndex(in: tokens, interner: interner)
        case .constructorDecl:
            constructorParameterOpenParenIndex(in: tokens)
        default:
            tokens.firstIndex(where: { token in
                token.kind == .symbol(.lParen)
            })
        }
    }

    func classPrimaryConstructorOpenParenIndex(
        in tokens: [Token],
        interner: StringInterner
    ) -> Int? {
        guard let classIndex = classDeclarationKeywordIndex(in: tokens) else {
            return nil
        }
        var index = classIndex + 1
        if index < tokens.count, TypeRefParserCore.isTypeLikeNameToken(tokens[index].kind) {
            index += 1
        }
        if index < tokens.count, tokens[index].kind == .symbol(.lessThan) {
            index = skipBalancedBracket(
                in: tokens,
                from: index,
                open: .symbol(.lessThan),
                close: .symbol(.greaterThan)
            )
        }
        var depth = BracketDepth()
        while index < tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                let kind = token.kind
                if kind == .symbol(.lParen) {
                    return index
                }
                if kind == .symbol(.colon) || kind == .symbol(.lBrace) || kind == .symbol(.assign) {
                    return nil
                }
                if kind == .symbol(.at) {
                    if let parsed = AnnotationParsingSupport.parseAnnotation(
                        from: tokens, start: index, interner: interner, allowUseSiteTarget: false
                    ) {
                        index = parsed.nextIndex
                    } else {
                        index += 1
                    }
                    continue
                }
            }
            depth.track(token.kind)
            index += 1
        }
        return nil
    }

    func constructorParameterOpenParenIndex(in tokens: [Token]) -> Int? {
        guard let ctorIndex = tokens.firstIndex(where: { token in
            token.kind == .keyword(.constructor) || token.kind == .softKeyword(.constructor)
        }) else {
            return tokens.firstIndex(where: { token in
                token.kind == .symbol(.lParen)
            })
        }
        var index = ctorIndex + 1
        while index < tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.lParen) {
                return index
            }
            if kind == .symbol(.colon) || kind == .symbol(.lBrace) {
                return nil
            }
            index += 1
        }
        return nil
    }

    func appendValueParameter(
        from tokens: [Token],
        into parameters: inout [ValueParamDecl],
        interner: StringInterner,
        astArena: ASTArena
    ) {
        let split = splitDefaultValue(tokens)
        let withoutDefault = split.withoutDefault
        let hasDefaultValue = split.defaultTokens != nil
        guard !withoutDefault.isEmpty else {
            return
        }

        // Parse leading annotations (e.g. @field:FieldMark, @Deprecated("msg"))
        // and skip past them so their colons are not confused with the name:type colon.
        var parsedAnnotations: [AnnotationNode] = []
        var annotationScanIndex = 0
        while annotationScanIndex < withoutDefault.count,
              withoutDefault[annotationScanIndex].kind == .symbol(.at) {
            if let parsed = AnnotationParsingSupport.parseAnnotation(
                from: withoutDefault, start: annotationScanIndex, interner: interner, allowUseSiteTarget: true
            ) {
                parsedAnnotations.append(parsed.annotation)
                annotationScanIndex = parsed.nextIndex
            } else {
                annotationScanIndex += 1
            }
        }
        let afterAnnotations = annotationScanIndex

        let colonIndex = withoutDefault[afterAnnotations...].firstIndex(where: { token in
            if case .symbol(.colon) = token.kind {
                return true
            }
            return false
        })

        let nameSearchTokens: ArraySlice<Token> = if let colonIndex {
            withoutDefault[..<colonIndex]
        } else {
            withoutDefault[...]
        }

        guard let nameToken = nameSearchTokens.last(where: { token in
            if isParameterModifierToken(token) {
                return false
            }
            return TypeRefParserCore.isTypeLikeNameToken(token.kind)
        }) else {
            return
        }
        guard let name = internedIdentifier(from: nameToken, interner: interner) else {
            return
        }
        if case let .keyword(keyword) = nameToken.kind,
           isLeadingDeclarationKeyword(keyword),
           keyword != .value,
           keyword != .data
        {
            return
        }

        let typeRef: TypeRefID?
        if let colonIndex {
            let typeTokens = Array(withoutDefault[(colonIndex + 1)...])
            typeRef = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
        } else {
            typeRef = nil
        }

        let isVararg = withoutDefault.contains(where: { token in
            if case .keyword(.vararg) = token.kind {
                return true
            }
            return false
        })
        let isCrossinline = withoutDefault.contains(where: { token in
            if case .keyword(.crossinline) = token.kind {
                return true
            }
            return false
        })
        let isNoinline = withoutDefault.contains(where: { token in
            if case .keyword(.noinline) = token.kind {
                return true
            }
            return false
        })
        let isValProperty = withoutDefault.contains(where: { $0.kind == .keyword(.val) })
        let isVarProperty = withoutDefault.contains(where: { $0.kind == .keyword(.var) })
        let isOverrideProperty = withoutDefault.contains(where: { $0.kind == .keyword(.override) })
        let defaultValueExpr: ExprID?
        if let defaultTokens = split.defaultTokens?
            .filter({ $0.kind != .symbol(.semicolon) }),
            !defaultTokens.isEmpty
        {
            let parser = ExpressionParser(tokens: defaultTokens, interner: interner, astArena: astArena)
            defaultValueExpr = parser.parse()
        } else {
            defaultValueExpr = nil
        }
        parameters.append(ValueParamDecl(
            name: name,
            type: typeRef,
            isProperty: isValProperty || isVarProperty,
            isMutableProperty: isVarProperty,
            isOverrideProperty: isOverrideProperty,
            hasDefaultValue: hasDefaultValue,
            isVararg: isVararg,
            isCrossinline: isCrossinline,
            isNoinline: isNoinline,
            defaultValue: defaultValueExpr,
            annotations: parsedAnnotations
        ))
    }

    private func primaryConstructorPropertyDecls(
        from params: [ValueParamDecl],
        classRange: SourceRange,
        astArena: ASTArena
    ) -> [DeclID] {
        params.compactMap { param in
            guard param.isProperty else {
                return nil
            }
            let property = PropertyDecl(
                range: classRange,
                name: param.name,
                modifiers: param.isOverrideProperty ? [.override] : [],
                type: param.type,
                isVar: param.isMutableProperty,
                isSynthesizedPrimaryConstructorProperty: true
            )
            return astArena.appendDecl(.propertyDecl(property))
        }
    }
}
