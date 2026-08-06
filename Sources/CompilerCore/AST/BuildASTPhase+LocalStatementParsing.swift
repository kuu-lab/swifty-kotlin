
extension BuildASTPhase {
    func parseLocalDeclarationExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard !statementTokens.isEmpty else {
            return nil
        }
        var startIndex = 0
        while startIndex < statementTokens.count,
              case let .keyword(kw) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(kw)
        {
            startIndex += 1
        }
        guard startIndex < statementTokens.count else {
            return nil
        }
        let head = statementTokens[startIndex]
        let isMutable: Bool
        switch head.kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }

        let context = LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { tokens in
                ExpressionParser(tokens: tokens, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { typeTokens in
                self.parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
            },
            resolveDeclarationName: { token, interner in
                guard TypeRefParserCore.isTypeLikeNameToken(token.kind) else {
                    return nil
                }
                return self.internedIdentifier(from: token, interner: interner)
            }
        )
        return LocalStatementCore.parseLocalDeclaration(
            from: statementTokens,
            context: context,
            options: .declaration
        )
    }

    func parseLocalAssignmentExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        let context = LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { tokens in
                ExpressionParser(tokens: tokens, interner: interner, astArena: astArena).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil }
        )
        return LocalStatementCore.parseLocalAssignment(
            from: statementTokens,
            context: context,
            options: .blockExpression
        )
    }
}
