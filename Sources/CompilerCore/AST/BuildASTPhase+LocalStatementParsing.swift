
extension BuildASTPhase {
    func parseLocalDeclarationExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena
    ) -> ExprID? {
        guard !statementTokens.isEmpty else {
            return nil
        }
        if Self.isFullFormDestructuringHead(statementTokens) {
            return Self.parseDestructuringDeclarationExpr(
                from: statementTokens, startIndex: -1, isMutable: false,
                interner: interner, astArena: astArena, diagnostics: diagnostics
            )
        }
        var startIndex = 0
        var leadingModifiers: [(name: String, range: SourceRange)] = []
        while startIndex < statementTokens.count,
              case let .keyword(kw) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(kw)
        {
            leadingModifiers.append((kw.rawValue, statementTokens[startIndex].range))
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
        validateLocalVariableModifiers(leadingModifiers, isMutable: isMutable)

        if let destructuringResult = Self.parseDestructuringDeclarationExpr(
            from: statementTokens,
            startIndex: startIndex,
            isMutable: isMutable,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        ) {
            return destructuringResult
        }

        let context = LocalStatementCoreContext(
            interner: interner,
            astArena: astArena,
            parseExpression: { tokens in
                ExpressionParser(
                    tokens: tokens, interner: interner, astArena: astArena, diagnostics: self.diagnostics
                ).parse()
            },
            parseTypeReference: { typeTokens in
                self.parseTypeRef(from: typeTokens, interner: interner, astArena: astArena)
            },
            resolveDeclarationName: { token, interner in
                guard TypeRefParserCore.isDeclarationNameToken(token.kind) else {
                    return nil
                }
                return self.internedIdentifier(from: token, interner: interner)
            },
            diagnostics: self.diagnostics
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
                ExpressionParser(
                    tokens: tokens, interner: interner, astArena: astArena, diagnostics: self.diagnostics
                ).parse()
            },
            parseTypeReference: { _ in nil },
            resolveDeclarationName: { _, _ in nil },
            diagnostics: self.diagnostics
        )
        return LocalStatementCore.parseLocalAssignment(
            from: statementTokens,
            context: context,
            options: .blockExpression
        )
    }

    /// `suppressesLocalModifierDiagnostics` is set when the same token group is
    /// re-parsed as an anonymous-object member prefix, where visibility
    /// modifiers are legal and handled by the member-property builder.
    static func parseDestructuringDeclarationStatement(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena,
        diagnostics: DiagnosticEngine? = nil,
        suppressesLocalModifierDiagnostics: Bool = false
    ) -> ExprID? {
        var startIndex = 0
        var leadingModifiers: [(name: String, range: SourceRange)] = []
        while startIndex < statementTokens.count,
              case let .keyword(keyword) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(keyword)
        {
            leadingModifiers.append((keyword.rawValue, statementTokens[startIndex].range))
            startIndex += 1
        }
        guard startIndex < statementTokens.count else {
            return nil
        }
        if startIndex == 0, isFullFormDestructuringHead(statementTokens) {
            return parseDestructuringDeclarationExpr(
                from: statementTokens, startIndex: -1, isMutable: false,
                interner: interner, astArena: astArena, diagnostics: diagnostics
            )
        }
        let isMutable: Bool
        switch statementTokens[startIndex].kind {
        case .keyword(.val):
            isMutable = false
        case .keyword(.var):
            isMutable = true
        default:
            return nil
        }
        if !suppressesLocalModifierDiagnostics {
            diagnoseLocalVariableModifiers(leadingModifiers, isMutable: isMutable, diagnostics: diagnostics)
        }
        return parseDestructuringDeclarationExpr(
            from: statementTokens,
            startIndex: startIndex,
            isMutable: isMutable,
            interner: interner,
            astArena: astArena,
            diagnostics: diagnostics
        )
    }

    /// `[val a, var b] = x`: a statement-initial bracket group whose first entry
    /// declares a variable.
    static func isFullFormDestructuringHead(_ tokens: [Token]) -> Bool {
        guard tokens.count > 2, tokens[0].kind == .symbol(.lBracket) else { return false }
        return tokens[1].kind == .keyword(.val) || tokens[1].kind == .keyword(.var)
    }

    static func parseDestructuringDeclarationExpr(
        from statementTokens: [Token],
        startIndex: Int,
        isMutable: Bool,
        interner: StringInterner,
        astArena: ASTArena,
        diagnostics: DiagnosticEngine? = nil
    ) -> ExprID? {
        // After val/var keyword, expect `(` — but the CST parser may insert
        // a `missing(identifier)` token before it when it expects a property name.
        var afterKeyword = startIndex + 1
        while afterKeyword < statementTokens.count,
              case .missing = statementTokens[afterKeyword].kind
        {
            afterKeyword += 1
        }
        guard afterKeyword < statementTokens.count else {
            return nil
        }
        let openKind = statementTokens[afterKeyword].kind
        let openSymbol: Symbol
        let closeSymbol: Symbol
        switch openKind {
        case .symbol(.lParen):
            openSymbol = .lParen
            closeSymbol = .rParen
        case .symbol(.lBracket):
            openSymbol = .lBracket
            closeSymbol = .rBracket
        default:
            return nil
        }

        var depth = 0
        var closeParenIndex: Int?
        for i in afterKeyword ..< statementTokens.count {
            switch statementTokens[i].kind {
            case .symbol(openSymbol):
                depth += 1
            case .symbol(closeSymbol):
                depth -= 1
                if depth == 0 {
                    closeParenIndex = i
                    break
                }
            default:
                break
            }
            if closeParenIndex != nil { break }
        }
        guard let closeParenIndex else {
            return nil
        }

        let innerTokens = Array(statementTokens[(afterKeyword + 1) ..< closeParenIndex])
        let isSquare = openSymbol == .lBracket
        guard let entries = parseDestructuringEntries(innerTokens, interner: interner, allowsFullForm: isSquare) else {
            return nil
        }
        let names = entries.names
        guard !names.isEmpty else {
            return nil
        }

        var assignIndex: Int?
        for i in (closeParenIndex + 1) ..< statementTokens.count where statementTokens[i].kind == .symbol(.assign) {
            assignIndex = i
            break
        }
        guard let assignIndex else {
            return nil
        }

        let initializerTokens = statementTokens[(assignIndex + 1)...].filter { token in
            token.kind != .symbol(.semicolon)
        }
        guard !initializerTokens.isEmpty else {
            return nil
        }
        let parser = ExpressionParser(
            tokens: initializerTokens[...], interner: interner, astArena: astArena, diagnostics: diagnostics
        )
        guard let initializerExpr = parser.parse() else {
            return nil
        }

        let rangeStart = statementTokens[0].range.start
        let end = astArena.exprRange(initializerExpr)?.end ?? statementTokens.last?.range.end ?? statementTokens[max(startIndex, 0)].range.end
        let range = SourceRange(start: rangeStart, end: end)

        let declExpr = astArena.appendExpr(.destructuringDecl(
            names: names,
            isMutable: isMutable,
            initializer: initializerExpr,
            range: range
        ))
        astArena.setDestructuringDeclLayout(
            DestructuringDeclLayout(
                syntax: isSquare ? .squareBrackets : .parentheses,
                properties: entries.properties,
                mutableFlags: entries.mutableFlags
            ),
            for: declExpr
        )
        return declExpr
    }

    /// Splits the inside of `( ... )` / `[ ... ]` into entries. Supports the
    /// Kotlin 2.4 forms `name`, `name = property` and (brackets only) the full
    /// form `val name` / `var name`. Returns nil for a mixed full form, where
    /// some entries assign to existing variables.
    private static func parseDestructuringEntries(
        _ innerTokens: [Token],
        interner: StringInterner,
        allowsFullForm: Bool
    ) -> (names: [InternedString?], properties: [InternedString?], mutableFlags: [Bool])? {
        var entryTokens: [[Token]] = []
        var current: [Token] = []
        var depth = BracketDepth()
        for token in innerTokens {
            if depth.isAtTopLevel, token.kind == .symbol(.comma) {
                entryTokens.append(current)
                current = []
                continue
            }
            depth.track(token.kind)
            current.append(token)
        }
        if !current.isEmpty { entryTokens.append(current) }

        func nameOf(_ token: Token) -> InternedString?? {
            switch token.kind {
            case let .identifier(name):
                interner.resolve(name) == "_" ? .some(nil) : .some(name)
            case let .backtickedIdentifier(name):
                .some(name)
            case let .keyword(keyword):
                // Contextual keywords like `value` are valid identifiers here.
                .some(interner.intern(keyword.rawValue))
            case let .softKeyword(soft):
                .some(interner.intern(soft.rawValue))
            default:
                nil
            }
        }

        var names: [InternedString?] = []
        var properties: [InternedString?] = []
        var mutableFlags: [Bool] = []
        var declaringEntries = 0
        for var tokens in entryTokens {
            var entryMutable: Bool?
            if allowsFullForm, tokens.count > 1 {
                if tokens[0].kind == .keyword(.val) {
                    entryMutable = false
                    tokens.removeFirst()
                } else if tokens[0].kind == .keyword(.var) {
                    entryMutable = true
                    tokens.removeFirst()
                }
            }
            guard let first = tokens.first, let name = nameOf(first) else {
                continue
            }
            var property: InternedString?
            if tokens.count >= 3, tokens[1].kind == .symbol(.assign), let target = nameOf(tokens[2]) {
                property = target
            }
            names.append(name)
            properties.append(property)
            mutableFlags.append(entryMutable ?? false)
            if entryMutable != nil { declaringEntries += 1 }
        }
        if allowsFullForm, declaringEntries > 0 {
            guard declaringEntries == names.count else { return nil }
        } else {
            mutableFlags = []
        }
        guard !names.isEmpty else { return nil }
        return (names, properties, mutableFlags)
    }

    /// KUU-1407: local variables reject every declaration modifier except
    /// `lateinit` on `var`s (JVM reports them as compile errors).
    private func validateLocalVariableModifiers(
        _ modifiers: [(name: String, range: SourceRange)],
        isMutable: Bool
    ) {
        Self.diagnoseLocalVariableModifiers(modifiers, isMutable: isMutable, diagnostics: diagnostics)
    }

    static func diagnoseLocalVariableModifiers(
        _ modifiers: [(name: String, range: SourceRange)],
        isMutable: Bool,
        diagnostics: DiagnosticEngine?
    ) {
        for modifier in modifiers {
            if modifier.name == "lateinit" {
                if !isMutable {
                    diagnostics?.error(
                        "KSWIFTK-SEMA-0418",
                        "'lateinit' modifier is allowed only on mutable properties.",
                        range: modifier.range
                    )
                }
                continue
            }
            diagnostics?.error(
                "KSWIFTK-SEMA-0400",
                "modifier '\(modifier.name)' is not applicable to 'local variable'.",
                range: modifier.range
            )
        }
    }
}
