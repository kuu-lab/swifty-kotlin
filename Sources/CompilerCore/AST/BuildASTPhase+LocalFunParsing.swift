
extension BuildASTPhase {
    func parseLocalFunDeclExpr(
        from statementTokens: [Token],
        interner: StringInterner,
        astArena: ASTArena,
        bodyOverride: FunctionBody? = nil,
        isAnonymousFunction: Bool = false
    ) -> ExprID? {
        guard !statementTokens.isEmpty else {
            return nil
        }

        var startIndex = 0
        var contextReceivers: [ContextReceiverDecl] = []
        var contextReceiverTokens: [Token] = []
        if statementTokens.first?.kind == .softKeyword(.context),
           statementTokens.count > 1,
           statementTokens[1].kind == .symbol(.lParen)
        {
            var depth = 0
            var closingIndex: Int?
            for index in 1 ..< statementTokens.count {
                switch statementTokens[index].kind {
                case .symbol(.lParen): depth += 1
                case .symbol(.rParen):
                    depth -= 1
                    if depth == 0 {
                        closingIndex = index
                        break
                    }
                default: break
                }
                if closingIndex != nil { break }
            }
            if let closingIndex {
                contextReceiverTokens = Array(statementTokens[0 ... closingIndex])
                startIndex = closingIndex + 1
            }
        }
        var isSuspend = false
        var isTailrec = false
        var isInfix = false
        var hasOperator = false
        var hasExternal = false
        var leadingModifiers: [(name: String, range: SourceRange)] = []
        while startIndex < statementTokens.count,
              case let .keyword(keyword) = statementTokens[startIndex].kind,
              KotlinParser.isDeclarationModifierKeyword(keyword)
        {
            if keyword == .suspend {
                isSuspend = true
            }
            if keyword == .tailrec { isTailrec = true }
            if keyword == .infix { isInfix = true }
            if keyword == .operator { hasOperator = true }
            if keyword == .external { hasExternal = true }
            leadingModifiers.append((keyword.rawValue, statementTokens[startIndex].range))
            startIndex += 1
        }

        guard startIndex < statementTokens.count else {
            return nil
        }

        let head = statementTokens[startIndex]
        guard case .keyword(.fun) = head.kind
        else {
            return nil
        }
        // `fun(...)` is an anonymous function expression. Lambda-body parsing
        // probes local declarations before ordinary expressions, so let this
        // shape fall through to the expression parser.
        if statementTokens.indices.contains(startIndex + 1),
           statementTokens[startIndex + 1].kind == .symbol(.lParen)
        {
            return nil
        }
        // Parse the context clause only after `fun` is confirmed: a statement
        // like `context(Tag("x")) { ... }` is a call to the stdlib `context`
        // helper, not a declaration, and must not emit receiver diagnostics.
        if !contextReceiverTokens.isEmpty {
            contextReceivers = parseContextReceivers(
                from: contextReceiverTokens,
                interner: interner,
                astArena: astArena
            )
        }
        // KUU-1407: local functions accept only `suspend`/`infix`/`operator`/
        // `tailrec` modifiers on JVM; `inline` gets its own error.
        for modifier in leadingModifiers {
            switch modifier.name {
            case "suspend", "infix", "operator", "tailrec":
                continue
            case "inline":
                diagnostics?.error(
                    "KSWIFTK-SEMA-0400",
                    "local inline functions are not yet supported.",
                    range: modifier.range
                )
            default:
                diagnostics?.error(
                    "KSWIFTK-SEMA-0400",
                    "modifier '\(modifier.name)' is not applicable to 'local function'.",
                    range: modifier.range
                )
            }
        }

        let funTokens = Array(statementTokens[startIndex...])
        let typeParams: [TypeParamDecl]
        if let funIndex = funTokens.firstIndex(where: { $0.kind == .keyword(.fun) }),
           funIndex + 1 < funTokens.count,
           funTokens[funIndex + 1].kind == .symbol(.lessThan)
        {
            let typeParamsEnd = skipBalancedBracket(
                in: funTokens,
                from: funIndex + 1,
                open: .symbol(.lessThan),
                close: .symbol(.greaterThan)
            )
            typeParams = parseTypeParamTokens(
                Array(funTokens[(funIndex + 1)..<typeParamsEnd]),
                interner: interner,
                astArena: astArena
            )
        } else {
            typeParams = []
        }

        guard let lParenIndex = functionParameterOpenParenIndex(in: funTokens),
              let nameToken = funTokens[..<lParenIndex].last(where: { token in
                  TypeRefParserCore.isDeclarationNameToken(token.kind)
              }),
              let name = internedIdentifier(from: nameToken, interner: interner)
        else {
            return nil
        }

        if hasOperator,
           !DeclarationPositionValidator.isLegalOperatorName(interner.resolve(name))
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0416",
                "'operator' modifier is not applicable: illegal function name.",
                range: nameToken.range
            )
        }

        let receiverType = declarationReceiverType(from: funTokens, interner: interner, astArena: astArena)

        var valueParams: [ValueParamDecl] = []
        var depth = BracketDepth()
        var paramTokens: [Token] = []
        var index = lParenIndex + 1
        while index < funTokens.count {
            let token = funTokens[index]
            if token.kind == .symbol(.rParen), depth.paren == 0 {
                break
            }
            depth.track(token.kind)
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena,
                                     allowsImplicitParameterTypes: isAnonymousFunction)
                paramTokens.removeAll(keepingCapacity: true)
            } else {
                paramTokens.append(token)
            }
            index += 1
        }
        if !paramTokens.isEmpty {
            appendValueParameter(from: paramTokens, into: &valueParams, interner: interner, astArena: astArena,
                                 allowsImplicitParameterTypes: isAnonymousFunction)
        }

        guard index < funTokens.count, funTokens[index].kind == .symbol(.rParen) else {
            return nil
        }
        index += 1

        if !isAnonymousFunction {
            for param in valueParams where param.type == nil {
                diagnostics?.error(
                    "KSWIFTK-SEMA-0033",
                    "An explicit type is required on value parameter '\(interner.resolve(param.name))'.",
                    range: head.range
                )
            }
        }

        // kotlinc requires `infix` functions to be members or extension
        // functions with exactly one non-vararg value parameter; a local
        // function is only eligible through an extension receiver.
        if isInfix,
           isAnonymousFunction || receiverType == nil
               || valueParams.count != 1
               || valueParams[0].isVararg
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0431",
                "'infix' modifier is inapplicable to this function.",
                range: leadingModifiers.first(where: { $0.name == "infix" })?.range ?? head.range
            )
        }

        // KUU-3149: kotlinc also checks `operator` arity/eligibility on local
        // functions; a local function is never a member, so it qualifies only
        // through an extension receiver.
        if hasOperator,
           let violation = DeclarationPositionValidator.operatorEligibilityViolation(
               name: interner.resolve(name),
               isMember: false,
               isExtension: receiverType != nil,
               isSuspend: isSuspend,
               valueParams: valueParams
           )
        {
            diagnostics?.error(
                "KSWIFTK-SEMA-0439",
                "'operator' modifier is not applicable: \(violation).",
                range: leadingModifiers.first(where: { $0.name == "operator" })?.range ?? head.range
            )
        }

        let returnType = parseReturnTypeAnnotation(
            from: funTokens, index: &index, interner: interner, astArena: astArena
        )

        let body: FunctionBody
        if let bodyOverride {
            body = bodyOverride
        } else if index < funTokens.count, funTokens[index].kind == .symbol(.assign) {
            index += 1
            // Only strip top-level semicolons (matching filterTopLevelSemicolons'
            // caller convention) so a nested block in the expression body — e.g.
            // `= if (c) { a; b } else d` — keeps its own statement separator.
            let exprTokens = filterTopLevelSemicolons(funTokens[index...])
            let parser = ExpressionParser(
                tokens: exprTokens, interner: interner, astArena: astArena, diagnostics: diagnostics
            )
            if let exprID = parser.parse(), let exprRange = astArena.exprRange(exprID) {
                body = .expr(exprID, exprRange)
            } else {
                body = .unit
            }
        } else if index < funTokens.count, funTokens[index].kind == .symbol(.lBrace) {
            body = parseBraceBody(
                from: funTokens, index: &index, interner: interner, astArena: astArena
            )
        } else {
            body = .unit
        }

        let isSyntheticAnonymous = interner.resolve(name).hasPrefix("__AnonymousFunction_")
        if body == .unit, !hasExternal, !isSyntheticAnonymous {
            diagnostics?.error(
                "KSWIFTK-SEMA-0426",
                "function '\(interner.resolve(name))' must have a body.",
                range: head.range
            )
        }

        let end: SourceLocation = switch body {
        case let .block(_, range):
            range.end
        case let .expr(_, range):
            range.end
        case .unit:
            statementTokens.last?.range.end ?? head.range.end
        }
        let range = SourceRange(start: head.range.start, end: end)
        let declaration = astArena.appendExpr(.localFunDecl(
            name: name,
            receiverType: receiverType,
            valueParams: valueParams,
            returnType: returnType,
            body: body,
            isSuspend: isSuspend,
            range: range,
            typeParams: typeParams,
            isTailrec: isTailrec
        ))
        if !contextReceivers.isEmpty {
            astArena.setLocalFunContextReceivers(contextReceivers, for: declaration)
        }
        if leadingModifiers.contains(where: { $0.name == "tailrec" }) {
            astArena.markLocalTailrecFunction(declaration)
        }
        if isInfix { astArena.markInfixFunction(declaration) }
        if hasOperator { astArena.markOperatorFunction(declaration) }
        return declaration
    }

    private func parseReturnTypeAnnotation(
        from statementTokens: [Token],
        index: inout Int,
        interner: StringInterner,
        astArena: ASTArena
    ) -> TypeRefID? {
        guard index < statementTokens.count, statementTokens[index].kind == .symbol(.colon) else {
            return nil
        }
        let colonToken = statementTokens[index]
        index += 1
        var typeTokens: [Token] = []
        var typeDepth = BracketDepth()
        while index < statementTokens.count {
            let token = statementTokens[index]
            if typeDepth.isAtTopLevel {
                if token.kind == .symbol(.lBrace) || token.kind == .symbol(.assign) {
                    break
                }
            }
            typeDepth.track(token.kind)
            typeTokens.append(token)
            index += 1
        }
        guard let returnType = parseTypeRef(from: typeTokens, interner: interner, astArena: astArena) else {
            let following = index < statementTokens.count ? statementTokens[index] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? colonToken.range
            )
            return nil
        }
        return returnType
    }

    private func parseBraceBody(
        from statementTokens: [Token],
        index: inout Int,
        interner: StringInterner,
        astArena: ASTArena
    ) -> FunctionBody {
        var braceDepth = 0
        var bodyTokens: [Token] = []
        let braceStart = index
        while index < statementTokens.count {
            let token = statementTokens[index]
            if token.kind == .symbol(.lBrace) {
                braceDepth += 1
            } else if token.kind == .symbol(.rBrace) {
                braceDepth -= 1
                if braceDepth == 0 {
                    index += 1
                    break
                }
            }
            if braceDepth >= 1, !(braceDepth == 1 && token.kind == .symbol(.lBrace)) {
                bodyTokens.append(token)
            }
            index += 1
        }
        if !bodyTokens.isEmpty {
            let stmtGroups = splitTokensIntoStatements(bodyTokens)
            var blockExprs: [ExprID] = []
            for rawStmtTokens in stmtGroups {
                // Only strip top-level semicolons here (matching the CST-driven
                // path in blockExpressions/collectBlockStatementGroups) so a
                // nested block's own semicolon-separated statements — e.g.
                // `if (c) { a; b }` — survive to be split by ExpressionParser.
                let filtered = filterTopLevelSemicolons(rawStmtTokens[...])
                guard !filtered.isEmpty else { continue }
                if let exprID = parseStatementGroup(
                    raw: rawStmtTokens, filtered: filtered, interner: interner, astArena: astArena
                ) {
                    blockExprs.append(exprID)
                }
            }
            if !blockExprs.isEmpty,
               let firstRange = astArena.exprRange(blockExprs.first!),
               let lastRange = astArena.exprRange(blockExprs.last!)
            {
                let bodyRange = SourceRange(start: firstRange.start, end: lastRange.end)
                return .block(blockExprs, bodyRange)
            } else {
                let bodyRange = SourceRange(
                    start: statementTokens[braceStart].range.start,
                    end: statementTokens[min(index, statementTokens.count - 1)].range.end
                )
                return .block([], bodyRange)
            }
        } else {
            let bodyRange = SourceRange(
                start: statementTokens[braceStart].range.start,
                end: statementTokens[min(index, statementTokens.count - 1)].range.end
            )
            return .block([], bodyRange)
        }
    }
}
