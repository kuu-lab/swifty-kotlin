
extension BuildASTPhase.ExpressionParser {
    func parseLambdaLiteral(
        label: InternedString? = nil,
        start: SourceLocation? = nil
    ) -> ExprID? {
        guard matches(.symbol(.lBrace)) else {
            return nil
        }
        let savedIndex = index
        guard let openBrace = consume() else {
            return nil
        }

        let (bodyTokens, end, balanced) = consumeBalancedBraceBody(fallbackEnd: openBrace.range.end)
        guard balanced else {
            index = savedIndex
            return nil
        }

        if let arrowIndex = lambdaArrowIndex(in: bodyTokens) {
            let paramTokens = Array(bodyTokens[..<arrowIndex])
            let lambdaBodySlice = bodyTokens[(arrowIndex + 1)...]

            let bodyStart = astArena.exprs.count
            let parsedBody = parseLambdaBody(bodySlice: lambdaBodySlice, fallbackStart: openBrace.range.end)
            // Include callable references and names inside string templates so
            // generated parameters cannot shadow a user binding or lookup.
            var bodyNames = Set(lambdaBodySlice.compactMap { tokenText($0) })
            bodyNames.formUnion(astArena.exprs.dropFirst(bodyStart).compactMap { expr -> InternedString? in
                switch expr {
                case let .nameRef(name, _), let .callableRef(_, name, _): name
                default: nil
                }
            })
            let parsedParams = parseLambdaParams(from: paramTokens, avoidingNames: bodyNames)
            let range = SourceRange(start: start ?? openBrace.range.start, end: end)
            let bodyExpr = wrapLambdaDestructuring(params: parsedParams, body: parsedBody, range: range)
            let lambdaID = astArena.appendExpr(.lambdaLiteral(
                params: parsedParams.map(\.name), body: bodyExpr, label: label, range: range
            ))
            if parsedParams.contains(where: { $0.typeRef != nil }) {
                astArena.setLambdaParamTypeRefs(parsedParams.map(\.typeRef), for: lambdaID)
            }
            return lambdaID
        }

        // `{ x: -> x }` — a `:` that introduces a parameter type annotation
        // with no type before `->` is rejected by kotlinc. Without this the
        // brace falls through to statement parsing and reports a misleading
        // unresolved-name error for the body instead.
        reportEmptyLambdaParamType(in: bodyTokens)

        // In expression position Kotlin treats bare braces as lambda literals,
        // including zero-argument lambdas like `{ 42 }`. Both trailing-lambda
        // call sites and plain expression contexts accept the same syntax.
        let bodyExpr = parseLambdaBody(bodySlice: bodyTokens[...], fallbackStart: openBrace.range.end)
        let range = SourceRange(start: start ?? openBrace.range.start, end: end)
        return astArena.appendExpr(.lambdaLiteral(params: [], body: bodyExpr, label: label, range: range))
    }

    func parseObjectLiteral() -> ExprID? {
        guard let objectToken = consume() else {
            return nil
        }
        var superTypes: [TypeRefID] = []
        var superTypeEntries: [SuperTypeEntry] = []
        // Only the (at most one) class supertype can carry a constructor
        // call `(args)` — interfaces are listed bare. Kept as a single list
        // rather than per-supertype since that is all `ObjectDecl` needs.
        var superTypeConstructorArgs: [CallArgument] = []
        var end = objectToken.range.end
        var bodyTokens: [Token] = []

        if consumeIf(.symbol(.colon)) != nil {
            while true {
                let typeStart = current()?.range.start ?? objectToken.range.start
                guard let superType = parseTypeReference(current()?.range ?? objectToken.range) else {
                    break
                }
                let typeEnd = index > 0 ? tokens[index - 1].range.end : typeStart
                superTypes.append(superType)
                var constructorArgs: [CallArgument] = []
                var hasConstructorCallSyntax = false
                if matches(.symbol(.lParen)) {
                    hasConstructorCallSyntax = true
                    let open = consume()
                    constructorArgs = parseCallArguments()
                    if let open {
                        _ = consumeCallArgumentsClose(open: open)
                    }
                    if !constructorArgs.isEmpty {
                        superTypeConstructorArgs = constructorArgs
                    }
                }
                var delegateExpression: ExprID?
                if consumeIf(.softKeyword(.by)) != nil {
                    // The object's body is not a trailing lambda argument to
                    // the delegate call. Parse the header expression separately,
                    // retaining commas inside calls and generic argument lists.
                    let delegateStart = index
                    var depth = BuildASTPhase.BracketDepth()
                    var delegateBraceTracker = DelegateExpressionBraceTracker()
                    delegateBraceTracker.note(.softKeyword(.by), atTopLevel: true)
                    while let token = current() {
                        if depth.isAtTopLevel {
                            if token.kind == .symbol(.lBrace),
                               delegateBraceTracker.braceContinuesDelegateExpression()
                            {
                                // A brace that belongs to the delegate
                                // expression (`by when (x) { ... }`,
                                // `by object : C { }`, ...) is part of the
                                // expression; a later top-level brace is the
                                // object literal's body.
                                delegateBraceTracker.note(token.kind, atTopLevel: true)
                                depth.track(token.kind)
                                _ = consume()
                                continue
                            }
                            if [.symbol(.lBrace), .symbol(.semicolon),
                                .symbol(.rParen), .symbol(.rBrace)].contains(token.kind)
                                || (token.kind == .symbol(.comma)
                                    && delegateBraceTracker.commaEndsSupertypeEntry)
                            {
                                break
                            }
                        }
                        delegateBraceTracker.note(token.kind, atTopLevel: depth.isAtTopLevel)
                        // Parenthesized expressions may contain comparisons;
                        // those angle tokens are not header type arguments.
                        if depth.isBracketBraceParenTopLevel
                            || (token.kind != .symbol(.lessThan) && token.kind != .symbol(.greaterThan))
                        {
                            depth.track(token.kind)
                        }
                        _ = consume()
                    }
                    let parser = BuildASTPhase.ExpressionParser(
                        tokens: tokens[delegateStart ..< index],
                        interner: interner,
                        astArena: astArena,
                        diagnostics: diagnostics
                    )
                    delegateExpression = parser.parse()
                }
                superTypeEntries.append(SuperTypeEntry(
                    typeRef: superType,
                    delegateExpression: delegateExpression,
                    constructorArgs: constructorArgs,
                    hasConstructorCallSyntax: hasConstructorCallSyntax,
                    range: SourceRange(start: typeStart, end: typeEnd)
                ))
                if consumeIf(.symbol(.comma)) != nil {
                    continue
                }
                break
            }
            if index > 0 {
                end = tokens[index - 1].range.end
            }
        }

        if matches(.symbol(.lBrace)), let openBrace = consume() {
            (bodyTokens, end, _) = consumeBalancedBraceBody(fallbackEnd: openBrace.range.end)
        }

        let range = SourceRange(start: objectToken.range.start, end: end)
        let declID = parseObjectLiteralDecl(
            superTypes: superTypes,
            superTypeEntries: superTypeEntries,
            superTypeConstructorArgs: superTypeConstructorArgs,
            bodyTokens: bodyTokens,
            range: range
        )
        return astArena.appendExpr(.objectLiteral(superTypes: superTypes, decl: declID, range: range))
    }

    func parseCallableReference(
        receiver: ExprID? = nil,
        receiverTypeRef: TypeRefID? = nil,
        receiverTypeRange: SourceRange? = nil
    ) -> ExprID? {
        guard let opToken = consume() else {
            return nil
        }
        guard let memberToken = current() else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0014",
                "Expected an identifier after '::'.",
                range: opToken.range
            )
            return nil
        }
        // `::class` is Kotlin's keyword-based class-literal form.
        let memberName: InternedString?
        if case .keyword(.class) = memberToken.kind {
            memberName = interner.intern("class")
        } else {
            memberName = tokenText(memberToken)
        }
        guard let memberName else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0014",
                "Expected an identifier after '::'.",
                range: opToken.range
            )
            return nil
        }
        _ = consume()
        let range = SourceRange(
            start: receiver.flatMap { astArena.exprRange($0)?.start }
                ?? receiverTypeRange?.start
                ?? opToken.range.start,
            end: memberToken.range.end
        )
        let reference = astArena.appendExpr(.callableRef(receiver: receiver, member: memberName, range: range))
        if let receiverTypeRef {
            astArena.setCallableRefReceiverTypeRef(reference, typeRef: receiverTypeRef)
        }
        return reference
    }

    /// On imbalance, `bodyTokens` holds everything scanned and `end` is the
    /// last token's end (or `fallbackEnd` if nothing was consumed) — the
    /// caller decides whether that's acceptable.
    private func consumeBalancedBraceBody(
        fallbackEnd: SourceLocation
    ) -> (bodyTokens: [Token], end: SourceLocation, balanced: Bool) {
        let bodyStart = index
        var depth = 1
        var end = fallbackEnd
        while let token = current() {
            _ = consume()
            end = token.range.end
            switch token.kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
            default:
                break
            }
            if depth == 0 {
                break
            }
        }
        let bodyEnd = depth == 0 ? index - 1 : index
        return (Array(tokens[bodyStart..<bodyEnd]), end, depth == 0)
    }

    /// Kotlin parses a control-structure body `{ params -> ... }` as a function
    /// literal rather than a block.
    func braceGroupStartsLambdaLiteral() -> Bool {
        guard matches(.symbol(.lBrace)) else {
            return false
        }
        var depth = 0
        var offset = index
        while offset < tokens.endIndex {
            switch tokens[offset].kind {
            case .symbol(.lBrace):
                depth += 1
            case .symbol(.rBrace):
                depth -= 1
            default:
                break
            }
            if depth == 0 {
                break
            }
            offset += 1
        }
        guard depth == 0 else {
            return false
        }
        let bodyTokens = Array(tokens[(index + 1) ..< offset])
        return lambdaArrowIndex(in: bodyTokens) != nil
    }

    private func lambdaArrowIndex(in tokens: [Token]) -> Int? {
        var depth = BuildASTPhase.BracketDepth()
        var candidates: [Int] = []
        for (idx, token) in tokens.enumerated() {
            if token.kind == .symbol(.arrow), depth.isAtTopLevel {
                candidates.append(idx)
            }
            depth.track(token.kind)
        }
        // A parameter with a function type (`f: (Int) -> Int`) places an
        // extra top-level `->` inside the parameter list, while an `as`/`is`
        // function-type operand in the body (`s as (Int) -> Int`) places one
        // after it. The lambda arrow is the last `->` whose prefix is a
        // well-formed parameter list — matching kotlinc, which parses the
        // parameter list (types included) and then expects `->`.
        for candidate in candidates.reversed() {
            if isWellFormedLambdaParameterList(tokens[..<candidate]) {
                return candidate
            }
        }
        return nil
    }

    struct LambdaParam {
        let name: InternedString
        let typeRef: TypeRefID?
        let destructuringNames: [InternedString?]?
        let destructuringSyntax: ForDestructuringSyntax?
    }

    private func parseLambdaParams(
        from tokens: [Token],
        avoidingNames: Set<InternedString>
    ) -> [LambdaParam] {
        guard !tokens.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var currentSegment: [Token] = []
        var depth = BuildASTPhase.BracketDepth()
        for token in tokens {
            if token.kind == .symbol(.comma), depth.isAtTopLevel {
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                    currentSegment = []
                }
                continue
            }
            depth.track(token.kind)
            currentSegment.append(token)
        }
        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        var params: [LambdaParam] = []
        var usedNames = avoidingNames.union(tokens.compactMap { tokenText($0) })
        for (index, segment) in segments.enumerated() {
            if let closeIndex = lambdaDestructuringCloseIndex(in: segment[...]),
               let destructuring = extractDestructuringParameter(from: Array(segment[...closeIndex]))
            {
                var parameterName = interner.intern("__destructured_\(index)")
                while usedNames.contains(parameterName) {
                    parameterName = interner.intern(interner.resolve(parameterName) + "_")
                }
                usedNames.insert(parameterName)
                params.append(LambdaParam(
                    name: parameterName,
                    typeRef: parseLambdaParamTypeAnnotation(in: segment, after: closeIndex),
                    destructuringNames: destructuring.names,
                    destructuringSyntax: destructuring.syntax
                ))
                continue
            }
            guard let nameIndex = segment.firstIndex(where: { token in
                token.kind.isLabelName
            }), let name = tokenText( segment[nameIndex]) else {
                continue
            }
            params.append(LambdaParam(
                name: name,
                typeRef: parseLambdaParamTypeAnnotation(in: segment, after: nameIndex),
                destructuringNames: nil,
                destructuringSyntax: nil
            ))
        }
        return params
    }

    private func parseLambdaParamTypeAnnotation(in segment: [Token], after nameIndex: Int) -> TypeRefID? {
        let colonIndex = nameIndex + 1
        guard colonIndex < segment.count, segment[colonIndex].kind == .symbol(.colon) else {
            return nil
        }
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            segment[(colonIndex + 1)...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics,
            recursionDepth: recursionDepth
        ) else {
            let following = colonIndex + 1 < segment.count ? segment[colonIndex + 1] : nil
            diagnostics?.error(
                "KSWIFTK-PARSE-0020",
                "Expected type after ':'.",
                range: following?.range ?? segment[colonIndex].range
            )
            return nil
        }
        return parsed.ref
    }

    private func extractDestructuringParameter(
        from paramTokens: [Token]
    ) -> (names: [InternedString?], syntax: ForDestructuringSyntax)? {
        guard paramTokens.count >= 2,
              let syntax = lambdaDestructuringSyntax(for: paramTokens[0].kind),
              let closeIndex = lambdaDestructuringCloseIndex(in: paramTokens[...]),
              closeIndex == paramTokens.count - 1
        else { return nil }
        let innerTokens = Array(paramTokens.dropFirst().dropLast())
        guard isDestructuringEntries(innerTokens[...]) else { return nil }
        let names = parseDestructuringNames(from: innerTokens)
        return names.isEmpty ? nil : (names, syntax)
    }

    private func parseDestructuringNames(from innerTokens: [Token]) -> [InternedString?] {
        var names: [InternedString?] = []
        var depth = BuildASTPhase.BracketDepth()
        var entryStart = innerTokens.startIndex
        for index in innerTokens.indices {
            if innerTokens[index].kind == .symbol(.comma), depth.isAtTopLevel {
                appendDestructuringName(in: innerTokens[entryStart ..< index], to: &names)
                entryStart = index + 1
            }
            depth.track(innerTokens[index].kind)
        }
        appendDestructuringName(in: innerTokens[entryStart...], to: &names)
        return names
    }

    private func appendDestructuringName(
        in entry: ArraySlice<Token>,
        to names: inout [InternedString?]
    ) {
        guard !entry.isEmpty else { return }
        var firstIndex = entry.startIndex
        if entry[firstIndex].kind == .keyword(.val) || entry[firstIndex].kind == .keyword(.var) {
            firstIndex = entry.index(after: firstIndex)
        }
        guard firstIndex < entry.endIndex,
              let name = tokenText(entry[firstIndex])
        else {
            return
        }
        names.append(interner.resolve(name) == "_" ? nil : name)
    }

    private func wrapLambdaDestructuring(
        params: [LambdaParam],
        body: ExprID,
        range: SourceRange
    ) -> ExprID {
        // Keep one parameter per argument; component declarations use the
        // expected type of their own parameter, including in mixed lists.
        let declarations = params.compactMap { param -> ExprID? in
            guard let names = param.destructuringNames,
                  let syntax = param.destructuringSyntax
            else { return nil }
            let initializer = astArena.appendExpr(.nameRef(param.name, range))
            let declaration = astArena.appendExpr(.destructuringDecl(
                names: names, isMutable: false, initializer: initializer, range: range
            ))
            astArena.setDestructuringDeclLayout(
                DestructuringDeclLayout(
                    syntax: syntax,
                    properties: Array(repeating: nil, count: names.count),
                    mutableFlags: []
                ),
                for: declaration
            )
            return declaration
        }
        guard !declarations.isEmpty else { return body }
        return astArena.appendExpr(.blockExpr(
            statements: declarations, trailingExpr: body, range: range
        ))
    }

    /// Whether `tokens` (everything before a top-level `->` inside `{ ... }`)
    /// form a well-formed lambda parameter list: either empty (`{ -> body }`),
    /// a nonempty destructuring group `(a)`, `(a, b)`, `[a]` or `[a, b]`, or a comma-separated list of
    /// `[annotations] name [: Type]` segments whose type parses completely
    /// (function types included). A body expression like `s as (Int) -> Int`
    /// leaves an `->` in the brace group; the strict check keeps it from being
    /// mistaken for `s as (Int)` parameters — `{ s as () -> Int }` is a lambda
    /// whose body casts `s`, and `if (c) { s as () -> Int }` is a plain block.
    private func isWellFormedLambdaParameterList(_ tokens: ArraySlice<Token>) -> Bool {
        if tokens.isEmpty { return true }
        let params = Array(tokens)
        if extractDestructuringParameter(from: params) != nil { return true }
        var depth = BuildASTPhase.BracketDepth()
        var segmentStart = params.startIndex
        for idx in params.indices {
            if params[idx].kind == .symbol(.comma), depth.isAtTopLevel {
                guard isWellFormedLambdaParamSegment(params[segmentStart ..< idx]) else {
                    return false
                }
                segmentStart = idx + 1
            }
            depth.track(params[idx].kind)
        }
        return isWellFormedLambdaParamSegment(params[segmentStart...])
    }

    private func isWellFormedLambdaParamSegment(_ segment: ArraySlice<Token>) -> Bool {
        var idx = segment.startIndex
        while idx < segment.endIndex, segment[idx].kind == .symbol(.at),
              let annotation = AnnotationParsingSupport.parseAnnotation(
                  from: Array(segment), start: idx - segment.startIndex,
                  interner: interner, allowUseSiteTarget: true
              )
        {
            idx = segment.startIndex + annotation.nextIndex
        }
        guard idx < segment.endIndex else { return false }
        if lambdaDestructuringSyntax(for: segment[idx].kind) != nil {
            // Destructuring parameters in either delimiter form can be mixed with
            // regular parameters and optionally followed by `: Type`.
            guard let closeIndex = lambdaDestructuringCloseIndex(in: segment[idx...]),
                  isDestructuringEntries(segment[(idx + 1)..<closeIndex])
            else {
                return false
            }
            idx = closeIndex + 1
        } else {
            guard tokenText( segment[idx]) != nil else {
                return false
            }
            idx += 1
        }
        if idx == segment.endIndex { return true }
        guard segment[idx].kind == .symbol(.colon) else { return false }
        let typeTokens = segment[(idx + 1)...]
        guard !typeTokens.isEmpty else { return false }
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            typeTokens,
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: nil,
            recursionDepth: recursionDepth
        ) else {
            return false
        }
        return parsed.consumed == typeTokens.count
    }

    private func reportEmptyLambdaParamType(in tokens: [Token]) {
        var depth = BuildASTPhase.BracketDepth()
        var previous: Token?
        for token in tokens {
            if depth.isAtTopLevel,
               token.kind == .symbol(.arrow),
               previous?.kind == .symbol(.colon)
            {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0020",
                    "Expected type after ':'.",
                    range: token.range
                )
                return
            }
            depth.track(token.kind)
            previous = token
        }
    }

    private func lambdaDestructuringCloseIndex(in tokens: ArraySlice<Token>) -> Int? {
        guard let openingKind = tokens.first?.kind else { return nil }
        let closingKind: TokenKind
        switch openingKind {
        case .symbol(.lParen): closingKind = .symbol(.rParen)
        case .symbol(.lBracket): closingKind = .symbol(.rBracket)
        default: return nil
        }
        var depth = 0
        for idx in tokens.indices {
            if tokens[idx].kind == openingKind {
                depth += 1
            } else if tokens[idx].kind == closingKind {
                depth -= 1
                if depth == 0 { return idx }
            }
        }
        return nil
    }

    private func lambdaDestructuringSyntax(for openingKind: TokenKind) -> ForDestructuringSyntax? {
        switch openingKind {
        case .symbol(.lParen): .parentheses
        case .symbol(.lBracket): .squareBrackets
        default: nil
        }
    }

    private func isDestructuringEntries(_ inner: ArraySlice<Token>) -> Bool {
        guard !inner.isEmpty else { return false }
        var depth = BuildASTPhase.BracketDepth()
        var entryStart = inner.startIndex
        var entryCount = 0
        var fullFormEntryCount = 0
        for idx in inner.indices {
            if inner[idx].kind == .symbol(.comma), depth.isAtTopLevel {
                let entry = inner[entryStart ..< idx]
                guard isDestructuringEntry(entry) else { return false }
                entryCount += 1
                if entry.first?.kind == .keyword(.val) || entry.first?.kind == .keyword(.var) {
                    fullFormEntryCount += 1
                }
                entryStart = idx + 1
            }
            depth.track(inner[idx].kind)
        }
        // Kotlin permits a trailing comma after the last component.
        if entryStart < inner.endIndex {
            let entry = inner[entryStart...]
            guard isDestructuringEntry(entry) else { return false }
            entryCount += 1
            if entry.first?.kind == .keyword(.val) || entry.first?.kind == .keyword(.var) {
                fullFormEntryCount += 1
            }
        }
        return fullFormEntryCount == 0 || fullFormEntryCount == entryCount
    }

    private func isDestructuringEntry(_ entry: ArraySlice<Token>) -> Bool {
        guard let first = entry.first else { return false }
        let isFullForm = first.kind == .keyword(.val) || first.kind == .keyword(.var)
        let declaration = isFullForm ? entry.dropFirst() : entry
        guard let declarationName = declaration.first,
              tokenText(declarationName) != nil
        else {
            return false
        }

        var depth = BuildASTPhase.BracketDepth()
        var assignmentIndex: Int?
        for index in declaration.indices.dropFirst() {
            if declaration[index].kind == .symbol(.assign), depth.isAtTopLevel {
                assignmentIndex = index
                break
            }
            depth.track(declaration[index].kind)
        }
        if let assignmentIndex {
            guard isFullForm,
                  isWellFormedLambdaParamSegment(declaration[declaration.startIndex ..< assignmentIndex])
            else {
                return false
            }
            let property = declaration.index(after: assignmentIndex)
            return property < declaration.endIndex
                && declaration.index(after: property) == declaration.endIndex
                && tokenText(declaration[property]) != nil
        }

        // Component annotations use the same name/type grammar as plain
        // parameters; reject expressions and incompletely parsed types.
        return isWellFormedLambdaParamSegment(declaration)
    }

}
