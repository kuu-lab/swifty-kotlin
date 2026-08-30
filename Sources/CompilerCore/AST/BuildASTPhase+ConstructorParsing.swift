
extension BuildASTPhase {
    private func blockChildren(of nodeID: NodeID, in arena: SyntaxArena) -> [NodeID] {
        arena.children(of: nodeID).compactMap { child in
            guard case let .node(id) = child, arena.node(id).kind == .block else { return nil }
            return id
        }
    }

    func declarationInitBlocks(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [FunctionBody] {
        var result: [FunctionBody] = []
        for bodyBlockID in blockChildren(of: nodeID, in: arena) {
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case let .node(statementID) = bodyChild,
                      isStatementLikeKind(arena.node(statementID).kind)
                else {
                    continue
                }
                let headerTokens = collectDirectTokens(from: statementID, in: arena).filter { token in
                    token.kind != .symbol(.semicolon)
                }
                guard let firstToken = headerTokens.first,
                      firstToken.kind == .softKeyword(.`init`)
                else {
                    continue
                }

                if let nestedBlockID = blockChildren(of: statementID, in: arena).first {
                    let exprs = blockExpressions(
                        from: nestedBlockID,
                        in: arena,
                        interner: interner,
                        astArena: astArena
                    )
                    result.append(.block(exprs, arena.node(nestedBlockID).range))
                    continue
                }

                if headerTokens.count > 1 {
                    let parser = ExpressionParser(
                        tokens: headerTokens.dropFirst(),
                        interner: interner,
                        astArena: astArena
                    )
                    if let exprID = parser.parse(),
                       let range = astArena.exprRange(exprID)
                    {
                        result.append(.expr(exprID, range))
                        continue
                    }
                }
                result.append(.unit)
            }
        }
        return result
    }

    func declarationSecondaryConstructors(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> [ConstructorDecl] {
        var result: [ConstructorDecl] = []
        for bodyBlockID in blockChildren(of: nodeID, in: arena) {
            // Annotations may appear as a preceding sibling statement node
            // before the constructorDecl node in the body block CST.
            // Accumulate tokens from sibling children so annotations are captured.
            var precedingTokens: [Token] = []
            for bodyChild in arena.children(of: bodyBlockID) {
                guard case let .node(ctorNodeID) = bodyChild,
                      arena.node(ctorNodeID).kind == .constructorDecl
                else {
                    switch bodyChild {
                    case let .token(tokenID):
                        if let tok = resolveToken(tokenID, in: arena) {
                            precedingTokens.append(tok)
                        }
                    case let .node(siblingID):
                        // Collect tokens from sibling nodes (e.g. statement wrapping @Annotation)
                        precedingTokens.append(contentsOf: collectTokens(from: siblingID, in: arena))
                    }
                    continue
                }
                let ctorNode = arena.node(ctorNodeID)
                let params = declarationValueParameters(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let delegationCall = extractDelegationCall(from: ctorNodeID, in: arena, interner: interner, astArena: astArena)
                let body: FunctionBody
                if let blockID = blockChildren(of: ctorNodeID, in: arena).first {
                    let exprs = blockExpressions(from: blockID, in: arena, interner: interner, astArena: astArena)
                    body = .block(exprs, arena.node(blockID).range)
                } else {
                    body = .unit
                }
                // Annotations from preceding sibling tokens + any inside the node
                let nodeTokens = collectTokens(from: ctorNodeID, in: arena)
                let combinedTokens = precedingTokens + nodeTokens
                let annotations = annotationsFromTokens(combinedTokens, interner: interner)
                precedingTokens.removeAll(keepingCapacity: true)
                result.append(ConstructorDecl(
                    range: ctorNode.range,
                    modifiers: declarationModifiers(from: ctorNodeID, in: arena),
                    annotations: annotations,
                    valueParams: params,
                    delegationCall: delegationCall,
                    body: body
                ))
            }
        }
        return result
    }

    func extractDelegationCall(
        from nodeID: NodeID,
        in arena: SyntaxArena,
        interner: StringInterner,
        astArena: ASTArena
    ) -> ConstructorDelegationCall? {
        let tokens = collectTokens(from: nodeID, in: arena)
        guard let parenIndex = tokens.firstIndex(where: { $0.kind == .symbol(.lParen) }) else {
            return nil
        }
        var index = skipBalancedBracket(in: tokens, from: parenIndex, open: .symbol(.lParen), close: .symbol(.rParen))

        guard index < tokens.count else { return nil }

        if tokens[index].kind == .symbol(.colon) {
            index += 1
        }

        guard index < tokens.count else { return nil }

        let kind: ConstructorDelegationKind
        if tokens[index].kind == .keyword(.this) {
            kind = .this
            index += 1
        } else if tokens[index].kind == .keyword(.super) {
            kind = .super_
            index += 1
        } else {
            return nil
        }

        let range = tokens[index - 1].range

        var args: [CallArgument] = []
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            let afterParen = skipBalancedBracket(in: tokens, from: index, open: .symbol(.lParen), close: .symbol(.rParen))
            let argTokens = Array(tokens[(index + 1)..<afterParen])
            let parser = ExpressionParser(tokens: argTokens, interner: interner, astArena: astArena)
            args = parser.parseCallArguments()
        }

        return ConstructorDelegationCall(kind: kind, args: args, range: range)
    }
}
