
extension BuildASTPhase {
    func declarationTypeParameters(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena? = nil
    ) -> [TypeParamDecl] {
        for child in arena.children(of: nodeID) {
            if case let .node(childID) = child,
               arena.node(childID).kind == .typeArgs
            {
                let tokens = collectTokens(from: childID, in: arena)
                return parseTypeParamTokens(tokens, interner: interner, astArena: astArena)
            }
        }
        return []
    }

    func parseTypeParamTokens(
        _ tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena?
    ) -> [TypeParamDecl] {
        var result: [TypeParamDecl] = []
        var angleDepth = 0
        var pendingVariance: TypeVariance = .invariant
        var pendingReified = false
        var pendingAnnotations: [AnnotationNode] = []
        var tokenIndex = 0

        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            if handleAngleBracketToken(token.kind, angleDepth: &angleDepth,
                                       pendingVariance: &pendingVariance, pendingReified: &pendingReified)
            {
                tokenIndex += 1
                continue
            }
            guard angleDepth == 1 else {
                tokenIndex += 1
                continue
            }
            if token.kind == .symbol(.at),
               let annotation = AnnotationParsingSupport.parseAnnotation(
                   from: tokens,
                   start: tokenIndex,
                   interner: interner,
                   allowUseSiteTarget: false
               )
            {
                pendingAnnotations.append(annotation.annotation)
                tokenIndex = annotation.nextIndex
                continue
            }
            if handleVarianceToken(token.kind, pendingVariance: &pendingVariance, pendingReified: &pendingReified) {
                tokenIndex += 1
                continue
            }
            guard TypeRefParserCore.isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner)
            else {
                tokenIndex += 1
                continue
            }
            tokenIndex += 1
            let upperBound = parseInlineUpperBound(tokens: tokens, tokenIndex: &tokenIndex,
                                                   interner: interner, astArena: astArena)
            result.append(TypeParamDecl(
                name: name, variance: pendingVariance, isReified: pendingReified,
                upperBounds: upperBound.map { [$0] } ?? [], annotations: pendingAnnotations
            ))
            pendingVariance = .invariant
            pendingReified = false
            pendingAnnotations = []
        }
        return result
    }

    private func handleAngleBracketToken(
        _ kind: TokenKind, angleDepth: inout Int,
        pendingVariance: inout TypeVariance, pendingReified: inout Bool
    ) -> Bool {
        switch kind {
        case .symbol(.lessThan):
            angleDepth += 1
            return true
        case .symbol(.greaterThan):
            angleDepth = max(0, angleDepth - 1)
            pendingVariance = .invariant
            pendingReified = false
            return true
        case .symbol(.comma):
            pendingVariance = .invariant
            pendingReified = false
            return true
        default:
            return false
        }
    }

    private func handleVarianceToken(
        _ kind: TokenKind, pendingVariance: inout TypeVariance, pendingReified: inout Bool
    ) -> Bool {
        switch kind {
        case .softKeyword(.out):
            pendingVariance = .out
            return true
        case .keyword(.in):
            pendingVariance = .in
            return true
        case .keyword(.reified):
            pendingReified = true
            return true
        default:
            return false
        }
    }

    private func parseInlineUpperBound(
        tokens: [Token], tokenIndex: inout Int,
        interner: StringInterner, astArena: ASTArena?
    ) -> TypeRefID? {
        guard tokenIndex < tokens.count,
              tokens[tokenIndex].kind == .symbol(.colon)
        else { return nil }
        let colonToken = tokens[tokenIndex]
        tokenIndex += 1
        var boundTokens: [Token] = []
        var innerDepth = BracketDepth()
        while tokenIndex < tokens.count {
            let tokenItem = tokens[tokenIndex]
            if innerDepth.isAtTopLevel {
                if tokenItem.kind == .symbol(.comma) || tokenItem.kind == .symbol(.greaterThan) {
                    break
                }
            }
            innerDepth.track(tokenItem.kind)
            boundTokens.append(tokenItem)
            tokenIndex += 1
        }
        guard let astArena else { return nil }
        guard let bound = parseTypeRef(from: boundTokens, interner: interner, astArena: astArena) else {
            let following = tokenIndex < tokens.count ? tokens[tokenIndex] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? colonToken.range
            )
            return nil
        }
        return bound
    }

    func declarationWhereClauses(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [(name: InternedString, bound: TypeRefID)] {
        declarationWhereClauseInfo(
            from: nodeID,
            in: arena,
            interner: interner,
            astArena: astArena
        ).whereClauses
    }

    func declarationWhereClauseInfo(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> (
        whereClauses: [(name: InternedString, bound: TypeRefID)],
        range: SourceRange?
    ) {
        let tokens = arena.node(nodeID).kind == .propertyDecl
            ? propertyHeadTokens(from: nodeID, in: arena, interner: interner)
            : collectTokens(from: nodeID, in: arena)
        let startIndex: Int?
        if arena.node(nodeID).kind == .funDecl {
            startIndex = findFunctionWhereKeywordIndex(in: tokens)
        } else {
            startIndex = findWhereKeywordIndex(in: tokens)
        }
        guard let startIndex else {
            return (whereClauses: [], range: nil)
        }
        let clauses = parseWhereClauseEntries(
            tokens: tokens,
            startIndex: startIndex,
            interner: interner,
            astArena: astArena,
            propertyAccessors: arena.node(nodeID).kind == .propertyDecl
        )
        return (whereClauses: clauses, range: tokens[startIndex].range)
    }

    private func findWhereKeywordIndex(in tokens: [Token]) -> Int? {
        var depth = BracketDepth()
        for (index, token) in tokens.enumerated() {
            depth.track(token.kind)
            if depth.isAtTopLevel, case .softKeyword(.where) = token.kind {
                return index
            }
        }
        return nil
    }

    private func findFunctionWhereKeywordIndex(in tokens: [Token]) -> Int? {
        guard let parameterCloseIndex = firstFunctionParameterCloseParen(in: tokens) else {
            return nil
        }

        var depth = BracketDepth()
        for index in (parameterCloseIndex + 1) ..< tokens.count {
            let token = tokens[index]
            if depth.isAtTopLevel {
                if case .softKeyword(.where) = token.kind,
                   index + 2 < tokens.count,
                   TypeRefParserCore.isTypeLikeNameToken(tokens[index + 1].kind),
                   tokens[index + 2].kind == .symbol(.colon)
                {
                    return index
                }
                if token.kind == .symbol(.assign)
                    || token.kind == .symbol(.lBrace)
                    || token.kind == .symbol(.semicolon)
                {
                    return nil
                }
            }
            depth.track(token.kind)
        }
        return nil
    }

    private func parseWhereClauseEntries(
        tokens: [Token], startIndex: Int,
        interner: StringInterner, astArena: ASTArena, propertyAccessors: Bool
    ) -> [(name: InternedString, bound: TypeRefID)] {
        var result: [(name: InternedString, bound: TypeRefID)] = []
        var index = startIndex + 1
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.lBrace) || token.kind == .symbol(.semicolon) {
                break
            }
            guard TypeRefParserCore.isTypeLikeNameToken(token.kind),
                  let name = internedIdentifier(from: token, interner: interner)
            else {
                index += 1
                continue
            }
            index += 1
            guard index < tokens.count, tokens[index].kind == .symbol(.colon) else {
                continue
            }
            let colonToken = tokens[index]
            index += 1
            let boundTokens = collectBoundTokens(tokens: tokens, index: &index)
            if let parsed = TypeRefParserCore.parseTypeRefPrefix(
                boundTokens[...], interner: interner, astArena: astArena,
                options: .declaration, diagnostics: diagnostics
            ), parsed.consumed == boundTokens.count
                || (propertyAccessors && isAccessorModifierSuffix(
                    Array(boundTokens.dropFirst(parsed.consumed)), interner: interner
                ))
            {
                result.append((name: name, bound: parsed.ref))
            } else {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0020",
                    "Expected type after ':'.",
                    range: boundTokens.first?.range ?? colonToken.range
                )
            }
            if index < tokens.count, tokens[index].kind == .symbol(.comma) {
                index += 1
            }
        }
        return result
    }

    private func isAccessorModifierSuffix(_ tokens: [Token], interner: StringInterner) -> Bool {
        var index = 0
        while index < tokens.count {
            switch tokens[index].kind {
            case .keyword(.inline), .keyword(.public), .keyword(.private), .keyword(.protected), .keyword(.internal):
                index += 1
            case .symbol(.at):
                guard let annotation = AnnotationParsingSupport.parseAnnotation(
                    from: tokens, start: index, interner: interner, allowUseSiteTarget: true
                ) else { return false }
                index = annotation.nextIndex
            default:
                return false
            }
        }
        return !tokens.isEmpty
    }

    private func collectBoundTokens(tokens: [Token], index: inout Int) -> [Token] {
        var boundTokens: [Token] = []
        var innerDepth = BracketDepth()
        while index < tokens.count {
            let tokenItem = tokens[index]
            if innerDepth.isAtTopLevel {
                let kind = tokenItem.kind
                let shouldBreak = kind == .symbol(.comma)
                    || kind == .symbol(.lBrace)
                    || kind == .symbol(.semicolon)
                    || kind == .symbol(.assign)
                if shouldBreak {
                    break
                }
            }
            innerDepth.track(tokenItem.kind)
            boundTokens.append(tokenItem)
            index += 1
        }
        return boundTokens
    }

    func applyWhereClauses(
        _ typeParams: [TypeParamDecl],
        whereClauses: [(name: InternedString, bound: TypeRefID)]
    ) -> [TypeParamDecl] {
        guard !whereClauses.isEmpty else { return typeParams }
        let clausesByName = Dictionary(grouping: whereClauses, by: \.name)
        return typeParams.map { param in
            let paramClauses = clausesByName[param.name] ?? []
            guard !paramClauses.isEmpty else {
                return param
            }
            let mergedBounds = param.upperBounds + paramClauses.map(\.bound)
            return TypeParamDecl(
                name: param.name,
                variance: param.variance,
                isReified: param.isReified,
                upperBounds: mergedBounds,
                annotations: param.annotations
            )
        }
    }
}
