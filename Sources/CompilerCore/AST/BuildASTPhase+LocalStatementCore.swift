
extension BuildASTPhase {
    struct LocalStatementCoreContext {
        let interner: StringInterner
        let astArena: ASTArena
        let parseExpression: (ArraySlice<Token>) -> ExprID?
        let parseTypeReference: ([Token]) -> TypeRefID?
        let resolveDeclarationName: (Token, StringInterner) -> InternedString?
    }

    struct LocalStatementCoreOptions {
        var allowMemberAssign: Bool
        var rejectValVarSimpleAssignLHS: Bool
        var strictInitializerWhenAssignPresent: Bool

        static let declaration = LocalStatementCoreOptions(
            allowMemberAssign: false,
            rejectValVarSimpleAssignLHS: true,
            strictInitializerWhenAssignPresent: true
        )

        static let blockExpression = LocalStatementCoreOptions(
            allowMemberAssign: true,
            rejectValVarSimpleAssignLHS: false,
            strictInitializerWhenAssignPresent: false
        )
    }

    enum LocalStatementCore {
        static func parseLocalDeclaration(
            from statementTokens: [Token],
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            parseLocalDeclaration(from: statementTokens[...], context: context, options: options)
        }

        static func parseLocalDeclaration(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            guard !statementTokens.isEmpty else {
                return nil
            }

            var startIndex = statementTokens.startIndex
            while startIndex < statementTokens.endIndex,
                  case let .keyword(keyword) = statementTokens[startIndex].kind,
                  KotlinParser.isDeclarationModifierKeyword(keyword)
            {
                startIndex = statementTokens.index(after: startIndex)
            }
            guard startIndex < statementTokens.endIndex else {
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

            if let destructuring = parseDestructuringDeclaration(
                from: statementTokens,
                startIndex: startIndex,
                isMutable: isMutable,
                context: context
            ) {
                return destructuring
            }

            var nameIndex: Int?
            var name: InternedString?
            var lookup = statementTokens.index(after: startIndex)
            while lookup < statementTokens.endIndex {
                if let resolved = context.resolveDeclarationName(statementTokens[lookup], context.interner) {
                    nameIndex = lookup
                    name = resolved
                    break
                }
                lookup = statementTokens.index(after: lookup)
            }
            guard let nameIndex,
                  let name
            else {
                return nil
            }

            var typeAnnotation: TypeRefID?
            var colonIndex: Int?
            var colonDepth = BuildASTPhase.BracketDepth()
            var scan = statementTokens.index(after: nameIndex)
            while scan < statementTokens.endIndex {
                let token = statementTokens[scan]
                if colonDepth.isAtTopLevel {
                    if token.kind == .symbol(.colon) {
                        colonIndex = scan
                        break
                    }
                    if token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon) {
                        break
                    }
                }
                colonDepth.track(token.kind)
                scan = statementTokens.index(after: scan)
            }

            if let colonIndex {
                var typeTokens: [Token] = []
                var typeDepth = BuildASTPhase.BracketDepth()
                var index = statementTokens.index(after: colonIndex)
                while index < statementTokens.endIndex {
                    let token = statementTokens[index]
                    if typeDepth.isAtTopLevel,
                       token.kind == .symbol(.assign) || token.kind == .symbol(.semicolon)
                    {
                        break
                    }
                    typeDepth.track(token.kind)
                    typeTokens.append(token)
                    index = statementTokens.index(after: index)
                }
                if !typeTokens.isEmpty {
                    typeAnnotation = context.parseTypeReference(typeTokens)
                }
            }

            var initializerStartIndex: Int?
            var isDelegated = false
            var assignDepth = BuildASTPhase.BracketDepth()
            var index = statementTokens.index(after: nameIndex)
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                if assignDepth.isAtTopLevel {
                    if token.kind == .symbol(.assign)
                        || token.kind == .softKeyword(.by)
                    {
                        isDelegated = token.kind == .softKeyword(.by)
                        initializerStartIndex = statementTokens.index(after: index)
                        break
                    }
                }
                assignDepth.track(token.kind)
                index = statementTokens.index(after: index)
            }

            var initializerExpr: ExprID?
            if let initializerStartIndex {
                let initTokens = stripSemicolons(statementTokens[initializerStartIndex ..< statementTokens.endIndex])
                guard !initTokens.isEmpty else {
                    return nil
                }
                let parsed = context.parseExpression(initTokens[...])
                if options.strictInitializerWhenAssignPresent, parsed == nil {
                    return nil
                }
                initializerExpr = parsed
            }

            if typeAnnotation == nil, initializerExpr == nil {
                return nil
            }

            let end: SourceLocation = if let initializerExpr {
                context.astArena.exprRange(initializerExpr)?.end
                    ?? statementTokens.last?.range.end
                    ?? head.range.end
            } else {
                statementTokens.last?.range.end ?? head.range.end
            }
            let range = SourceRange(start: statementTokens[statementTokens.startIndex].range.start, end: end)
            return context.astArena.appendExpr(.localDecl(
                name: name,
                isMutable: isMutable,
                typeAnnotation: typeAnnotation,
                initializer: initializerExpr,
                isDelegated: isDelegated,
                range: range
            ))
        }

        /// Parse destructuring declaration: `val (a, b, _) = expr`
        /// Returns nil if the tokens don't match the destructuring pattern.
        static func parseDestructuringDeclaration(
            from statementTokens: ArraySlice<Token>,
            startIndex: Int,
            isMutable: Bool,
            context: LocalStatementCoreContext
        ) -> ExprID? {
            // After val/var keyword, expect `(` — but the CST parser may insert
            // a `missing(identifier)` token before it when it expects a property name.
            var afterKeyword = statementTokens.index(after: startIndex)
            while afterKeyword < statementTokens.endIndex,
                  case .missing = statementTokens[afterKeyword].kind
            {
                afterKeyword = statementTokens.index(after: afterKeyword)
            }
            guard afterKeyword < statementTokens.endIndex,
                  statementTokens[afterKeyword].kind == .symbol(.lParen)
            else {
                return nil
            }

            var depth = 0
            var closeParenIndex: Int?
            for index in afterKeyword ..< statementTokens.endIndex {
                switch statementTokens[index].kind {
                case .symbol(.lParen):
                    depth += 1
                case .symbol(.rParen):
                    depth -= 1
                    if depth == 0 {
                        closeParenIndex = index
                    }
                default:
                    break
                }
                if closeParenIndex != nil { break }
            }
            guard let closeParenIndex else {
                return nil
            }

            let innerTokens = Array(statementTokens[statementTokens.index(after: afterKeyword) ..< closeParenIndex])
            let names = destructuringNames(from: innerTokens, interner: context.interner)
            guard !names.isEmpty else {
                return nil
            }

            var assignIndex: Int?
            for index in statementTokens.index(after: closeParenIndex) ..< statementTokens.endIndex
                where statementTokens[index].kind == .symbol(.assign)
            {
                assignIndex = index
                break
            }
            guard let assignIndex else {
                return nil
            }

            let initializerTokens = statementTokens[statementTokens.index(after: assignIndex)...].filter { token in
                token.kind != .symbol(.semicolon)
            }
            guard !initializerTokens.isEmpty,
                  let initializerExpr = context.parseExpression(initializerTokens[...])
            else {
                return nil
            }

            let rangeStart = statementTokens[statementTokens.startIndex].range.start
            let end = context.astArena.exprRange(initializerExpr)?.end
                ?? statementTokens.last?.range.end
                ?? statementTokens[startIndex].range.end
            return context.astArena.appendExpr(.destructuringDecl(
                names: names,
                isMutable: isMutable,
                initializer: initializerExpr,
                range: SourceRange(start: rangeStart, end: end)
            ))
        }

        /// Names between the destructuring parens, `nil` for `_`. Type annotations are skipped.
        private static func destructuringNames(
            from innerTokens: [Token],
            interner: StringInterner
        ) -> [InternedString?] {
            var names: [InternedString?] = []
            var idx = 0
            while idx < innerTokens.count {
                let token = innerTokens[idx]
                switch token.kind {
                case .symbol(.comma):
                    idx += 1
                    continue
                case let .identifier(name):
                    names.append(interner.resolve(name) == "_" ? nil : name)
                    idx += 1
                case let .backtickedIdentifier(name):
                    names.append(name)
                    idx += 1
                default:
                    if token.kind == .symbol(.colon) {
                        idx += 1
                        var typeDepth = BuildASTPhase.BracketDepth()
                        while idx < innerTokens.count {
                            let typeToken = innerTokens[idx]
                            if typeDepth.isAtTopLevel, typeToken.kind == .symbol(.comma) {
                                break
                            }
                            typeDepth.track(typeToken.kind)
                            idx += 1
                        }
                        continue
                    }
                    idx += 1
                }
            }
            return names
        }

        static func parseLocalAssignment(
            from statementTokens: [Token],
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            parseLocalAssignment(from: statementTokens[...], context: context, options: options)
        }

        static func parseLocalAssignment(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            guard statementTokens.count >= 2 else {
                return nil
            }

            if let postfixMutation = parsePostfixMutation(
                from: statementTokens,
                context: context,
                options: options
            ) {
                return postfixMutation
            }

            if let compound = parseCompoundAssignment(
                from: statementTokens,
                context: context,
                options: options
            ) {
                return compound
            }

            var assignIndex: Int?
            var depth = BuildASTPhase.BracketDepth()
            var index = statementTokens.startIndex
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                if token.kind == .symbol(.assign), depth.isAtTopLevel {
                    assignIndex = index
                    break
                }
                depth.track(token.kind)
                index = statementTokens.index(after: index)
            }
            guard let assignIndex,
                  assignIndex > statementTokens.startIndex
            else {
                return nil
            }

            let lhsTokens = stripSemicolons(statementTokens[statementTokens.startIndex ..< assignIndex])
            guard !lhsTokens.isEmpty else {
                return nil
            }

            let valueStart = statementTokens.index(after: assignIndex)
            let valueTokens = stripSemicolons(statementTokens[valueStart ..< statementTokens.endIndex])
            guard !valueTokens.isEmpty else {
                return nil
            }

            guard let lhsExpr = context.parseExpression(lhsTokens[...]),
                  let lhs = context.astArena.expr(lhsExpr),
                  let lhsRange = context.astArena.exprRange(lhsExpr),
                  let valueExpr = context.parseExpression(valueTokens[...])
            else {
                return nil
            }

            let end = context.astArena.exprRange(valueExpr)?.end
                ?? statementTokens.last?.range.end
                ?? lhsRange.end
            let range = SourceRange(start: lhsRange.start, end: end)

            switch lhs {
            case let .nameRef(name, _):
                if options.rejectValVarSimpleAssignLHS {
                    let text = context.interner.resolve(name)
                    if text == "val" || text == "var" {
                        return nil
                    }
                }
                return context.astArena.appendExpr(.localAssign(name: name, value: valueExpr, range: range))

            case let .memberCall(receiver, callee, typeArgs, args, _):
                guard options.allowMemberAssign,
                      typeArgs.isEmpty,
                      args.isEmpty
                else {
                    return nil
                }
                return context.astArena.appendExpr(.memberAssign(
                    receiver: receiver,
                    callee: callee,
                    value: valueExpr,
                    range: range
                ))

            case let .indexedAccess(receiver, indices, _):
                return context.astArena.appendExpr(.indexedAssign(
                    receiver: receiver,
                    indices: indices,
                    value: valueExpr,
                    range: range
                ))

            default:
                return nil
            }
        }

        private static func parsePostfixMutation(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            let strippedTokens = stripSemicolons(statementTokens)
            guard let lastToken = strippedTokens.last else {
                return nil
            }

            let op: CompoundAssignOp
            switch lastToken.kind {
            case .symbol(.plusPlus):
                op = .plusAssign
            case .symbol(.minusMinus):
                op = .minusAssign
            default:
                return nil
            }

            let lhsTokens = Array(strippedTokens.dropLast())
            guard !lhsTokens.isEmpty,
                  let lhsExpr = context.parseExpression(lhsTokens[...]),
                  let lhs = context.astArena.expr(lhsExpr),
                  let lhsRange = context.astArena.exprRange(lhsExpr)
            else {
                return nil
            }

            let oneExpr = context.astArena.appendExpr(.intLiteral(1, lastToken.range))
            let range = SourceRange(start: lhsRange.start, end: lastToken.range.end)

            switch lhs {
            case let .nameRef(name, _):
                if options.rejectValVarSimpleAssignLHS {
                    let text = context.interner.resolve(name)
                    if text == "val" || text == "var" {
                        return nil
                    }
                }
                return context.astArena.appendExpr(.compoundAssign(
                    op: op,
                    name: name,
                    value: oneExpr,
                    range: range
                ))

            case let .indexedAccess(receiver, indices, _):
                return context.astArena.appendExpr(.indexedCompoundAssign(
                    op: op,
                    receiver: receiver,
                    indices: indices,
                    value: oneExpr,
                    range: range
                ))

            case let .memberCall(receiver, callee, typeArgs, args, _):
                guard options.allowMemberAssign,
                      typeArgs.isEmpty,
                      args.isEmpty
                else {
                    return nil
                }
                return context.astArena.appendExpr(.memberCompoundAssign(
                    op: op,
                    receiver: receiver,
                    callee: callee,
                    value: oneExpr,
                    range: range
                ))

            default:
                return nil
            }
        }

        private static func parseCompoundAssignment(
            from statementTokens: ArraySlice<Token>,
            context: LocalStatementCoreContext,
            options: LocalStatementCoreOptions
        ) -> ExprID? {
            let compoundOps: [(TokenKind, CompoundAssignOp)] = [
                (.symbol(.plusAssign), .plusAssign),
                (.symbol(.minusAssign), .minusAssign),
                (.symbol(.starAssign), .timesAssign),
                (.symbol(.slashAssign), .divAssign),
                (.symbol(.percentAssign), .modAssign),
            ]

            var foundIndex: Int?
            var foundOp: CompoundAssignOp?
            var depth = BuildASTPhase.BracketDepth()
            var index = statementTokens.startIndex
            while index < statementTokens.endIndex {
                let token = statementTokens[index]
                for (kind, op) in compoundOps where token.kind == kind && depth.isAtTopLevel {
                    foundIndex = index
                    foundOp = op
                    break
                }
                if foundIndex != nil {
                    break
                }
                depth.track(token.kind)
                index = statementTokens.index(after: index)
            }

            guard let assignIndex = foundIndex,
                  let op = foundOp,
                  assignIndex > statementTokens.startIndex
            else {
                return nil
            }

            let lhsTokens = stripSemicolons(statementTokens[statementTokens.startIndex ..< assignIndex])
            guard !lhsTokens.isEmpty else {
                return nil
            }

            let valueStart = statementTokens.index(after: assignIndex)
            let valueTokens = stripSemicolons(statementTokens[valueStart ..< statementTokens.endIndex])
            guard !valueTokens.isEmpty else {
                return nil
            }

            guard let lhsExpr = context.parseExpression(lhsTokens[...]),
                  let lhs = context.astArena.expr(lhsExpr),
                  let lhsRange = context.astArena.exprRange(lhsExpr),
                  let valueExpr = context.parseExpression(valueTokens[...])
            else {
                return nil
            }

            let end = context.astArena.exprRange(valueExpr)?.end
                ?? statementTokens.last?.range.end
                ?? lhsRange.end
            let range = SourceRange(start: lhsRange.start, end: end)

            switch lhs {
            case let .nameRef(name, _):
                return context.astArena.appendExpr(.compoundAssign(
                    op: op,
                    name: name,
                    value: valueExpr,
                    range: range
                ))
            case let .indexedAccess(receiver, indices, _):
                return context.astArena.appendExpr(.indexedCompoundAssign(
                    op: op,
                    receiver: receiver,
                    indices: indices,
                    value: valueExpr,
                    range: range
                ))
            case let .memberCall(receiver, callee, typeArgs, args, _):
                guard options.allowMemberAssign,
                      typeArgs.isEmpty,
                      args.isEmpty
                else {
                    return nil
                }
                return context.astArena.appendExpr(.memberCompoundAssign(
                    op: op,
                    receiver: receiver,
                    callee: callee,
                    value: valueExpr,
                    range: range
                ))
            default:
                return nil
            }
        }

        private static func stripSemicolons(_ tokens: ArraySlice<Token>) -> [Token] {
            // Only strip semicolons at the outermost brace level so that
            // semicolons inside nested blocks / lambda bodies are preserved.
            var result: [Token] = []
            var braceDepth = 0
            for token in tokens {
                switch token.kind {
                case .symbol(.lBrace): braceDepth += 1
                case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
                default: break
                }
                if token.kind == .symbol(.semicolon), braceDepth == 0 {
                    continue
                }
                result.append(token)
            }
            return result
        }
    }
}
