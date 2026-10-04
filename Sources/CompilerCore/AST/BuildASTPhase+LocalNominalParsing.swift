extension BuildASTPhase {
    /// Parses `class`/`object` declarations that appear as block statements
    /// (`{ class L { ... } }`). Kotlin treats them as local nominal
    /// declarations: named exactly like file-scope ones but visible only to
    /// the statements that follow inside the same block.
    ///
    /// The CST path already tags these nodes `.classDecl`/`.objectDecl`, but
    /// statement parsing is token-driven everywhere (the CST statement group
    /// in `blockExpressions`, local-function bodies via `parseBraceBody`,
    /// lambda bodies via `parseBlockExpression`), so the declaration is
    /// reconstructed the same way `parseObjectLiteralFunctionDecl` rebuilds
    /// object-literal members: re-run `KotlinParser` over the statement's
    /// tokens and feed the resulting node to the shared `makeClassDecl` /
    /// `makeObjectDecl` builders. The decl is wrapped in `.localNominalDecl`
    /// so Sema can bind the name as a local rather than a file-level symbol.
    static func parseLocalNominalDeclExpr(
        from tokens: [Token],
        interner: StringInterner,
        astArena: ASTArena,
        diagnostics: DiagnosticEngine?
    ) -> ExprID? {
        guard let headIndex = localNominalDeclHeadIndex(in: tokens, interner: interner),
              localNominalDeclExpectsName(at: headIndex, in: tokens),
              let first = tokens.first,
              let last = tokens.last
        else {
            return nil
        }

        let eofRange = SourceRange(start: last.range.end, end: last.range.end)
        let parser = KotlinParser(
            tokens: tokens + [Token(kind: .eof, range: eofRange)],
            interner: interner,
            diagnostics: diagnostics ?? DiagnosticEngine()
        )
        let parsed = parser.parseFile()
        for child in parsed.arena.children(of: parsed.root) {
            guard case let .node(childID) = child else {
                continue
            }
            let declID: DeclID
            switch parsed.arena.node(childID).kind {
            case .classDecl:
                declID = astArena.appendDecl(.classDecl(
                    BuildASTPhase(diagnostics: diagnostics).makeClassDecl(
                        from: childID, in: parsed.arena, interner: interner, astArena: astArena
                    )
                ))
            case .objectDecl:
                declID = astArena.appendDecl(.objectDecl(
                    BuildASTPhase(diagnostics: diagnostics).makeObjectDecl(
                        from: childID, in: parsed.arena, interner: interner, astArena: astArena
                    )
                ))
            default:
                continue
            }
            return astArena.appendExpr(.localNominalDecl(
                declID: declID,
                range: SourceRange(start: first.range.start, end: last.range.end)
            ))
        }
        return nil
    }

    /// Scans the leading annotation / modifier prefix of a statement token
    /// group and returns the index of its first real token — the candidate
    /// `class`/`object` keyword position — or `nil` when some other token
    /// comes first (so `if (c) ...`, `foo.bar()` etc. bail out early).
    private static func localNominalDeclHeadIndex(
        in tokens: [Token],
        interner: StringInterner
    ) -> Int? {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.kind == .symbol(.at) {
                guard let parsed = AnnotationParsingSupport.parseAnnotation(
                    from: tokens, start: index, interner: interner, allowUseSiteTarget: true
                ) else {
                    return nil
                }
                index = parsed.nextIndex
                continue
            }
            if case let .keyword(keyword) = token.kind,
               KotlinParser.isDeclarationModifierKeyword(keyword)
            {
                index += 1
                continue
            }
            return index
        }
        return nil
    }

    /// `class`/`object` at `index` starts a named declaration only when a
    /// declaration name follows. `object` in particular also starts an
    /// *expression* (`object : Base {}`, `object {}`), which stays on the
    /// object-literal path — the name check is what keeps those apart.
    private static func localNominalDeclExpectsName(
        at index: Int,
        in tokens: [Token]
    ) -> Bool {
        switch tokens[index].kind {
        case .keyword(.class), .keyword(.object):
            break
        default:
            return false
        }
        guard index + 1 < tokens.count else {
            return false
        }
        return TypeRefParserCore.isDeclarationNameToken(tokens[index + 1].kind)
    }
}
