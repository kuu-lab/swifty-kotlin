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
        guard let headIndex = localNominalDeclHeadIndex(in: tokens, interner: interner)
        else {
            return nil
        }
        // KUU-1407: `interface`, `enum class` and `companion object` heads are
        // rejected outright inside function bodies on JVM. Returning an empty
        // block expression swallows the tokens so the generic expression
        // fallback does not re-parse the body and cascade secondary errors.
        func rejectedPlaceholder() -> ExprID {
            astArena.appendExpr(.blockExpr(
                statements: [], trailingExpr: nil,
                range: SourceRange(start: tokens[headIndex].range.start, end: tokens[headIndex].range.end)
            ))
        }
        switch tokens[headIndex].kind {
        case .keyword(.interface):
            diagnoseLocalInterface(at: headIndex, in: tokens, interner: interner, diagnostics: diagnostics)
            return rejectedPlaceholder()
        case .keyword(.fun) where headIndex + 1 < tokens.count
            && tokens[headIndex + 1].kind == .keyword(.interface):
            diagnoseLocalInterface(at: headIndex + 1, in: tokens, interner: interner, diagnostics: diagnostics)
            return rejectedPlaceholder()
        case .keyword(.companion):
            diagnostics?.error(
                "KSWIFTK-SEMA-0401",
                "modifier 'companion' is not applicable inside 'function'.",
                range: tokens[headIndex].range
            )
            return rejectedPlaceholder()
        default:
            break
        }
        guard localNominalDeclExpectsName(at: headIndex, in: tokens),
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
                        from: childID, in: parsed.arena, interner: interner, astArena: astArena,
                        companionSiteName: "local object"
                    )
                ))
            default:
                continue
            }
            // KUU-1407: validate the local declaration's own modifiers (e.g.
            // `sealed class` / `enum class` / visibility) and its members.
            DeclarationPositionValidator(
                astArena: astArena, interner: interner, diagnostics: diagnostics
            ).validate(declID: declID, site: .function)
            return astArena.appendExpr(.localNominalDecl(
                declID: declID,
                range: SourceRange(start: first.range.start, end: last.range.end)
            ))
        }
        return nil
    }

    /// Emits the JVM-parity diagnostic for a local `interface` declaration.
    private static func diagnoseLocalInterface(
        at index: Int,
        in tokens: [Token],
        interner: StringInterner,
        diagnostics: DiagnosticEngine?
    ) {
        var name = ""
        if index + 1 < tokens.count {
            switch tokens[index + 1].kind {
            case .identifier(let interned), .backtickedIdentifier(let interned):
                name = interner.resolve(interned)
            case .keyword(let keyword):
                name = keyword.rawValue
            case .softKeyword(let soft):
                name = soft.rawValue
            default:
                break
            }
        }
        diagnostics?.error(
            "KSWIFTK-SEMA-0429",
            "interface '\(name)' cannot be local. Try to use an anonymous object or abstract class instead.",
            range: tokens[index].range
        )
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
        let nameIndex: Int
        switch tokens[index].kind {
        case .keyword(.class), .keyword(.object):
            nameIndex = index + 1
        case .keyword(.enum):
            // `enum class X` is parsed as a class carrying the enum modifier;
            // the declaration-level check rejects it as a local class.
            guard index + 1 < tokens.count,
                  tokens[index + 1].kind == .keyword(.class)
            else {
                return false
            }
            nameIndex = index + 2
        default:
            return false
        }
        guard nameIndex < tokens.count else {
            return false
        }
        return TypeRefParserCore.isDeclarationNameToken(tokens[nameIndex].kind)
    }
}
