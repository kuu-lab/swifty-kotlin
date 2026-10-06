
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

            // Detect lambda destructuring: { (a, b) -> body }
            if let names = extractDestructuringNames(from: paramTokens) {
                let range = SourceRange(start: start ?? openBrace.range.start, end: end)
                return buildDestructuringLambda(
                    names: names, bodySlice: lambdaBodySlice,
                    fallbackStart: openBrace.range.end, range: range, label: label
                )
            }

            let parsedParams = parseLambdaParams(from: paramTokens)
            let bodyExpr = parseLambdaBody(bodySlice: lambdaBodySlice, fallbackStart: openBrace.range.end)
            let range = SourceRange(start: start ?? openBrace.range.start, end: end)
            let lambdaID = astArena.appendExpr(.lambdaLiteral(
                params: parsedParams.map(\.name), body: bodyExpr, label: label, range: range
            ))
            if parsedParams.contains(where: { $0.typeRef != nil }) {
                astArena.setLambdaParamTypeRefs(parsedParams.map(\.typeRef), for: lambdaID)
            }
            return lambdaID
        }

        // No-arrow lambda: `{ body }`.
        //
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
        // Only the (at most one) class supertype can carry a constructor
        // call `(args)` — interfaces are listed bare. Kept as a single list
        // rather than per-supertype since that is all `ObjectDecl` needs.
        var superTypeConstructorArgs: [CallArgument] = []
        var end = objectToken.range.end
        var bodyTokens: [Token] = []

        if consumeIf(.symbol(.colon)) != nil {
            while true {
                guard let superType = parseTypeReference(current()?.range ?? objectToken.range) else {
                    break
                }
                superTypes.append(superType)
                if matches(.symbol(.lParen)) {
                    _ = consume()
                    let args = parseCallArguments()
                    _ = consumeIf(.symbol(.rParen))
                    if !args.isEmpty {
                        superTypeConstructorArgs = args
                    }
                }
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
            superTypeConstructorArgs: superTypeConstructorArgs,
            bodyTokens: bodyTokens,
            range: range
        )
        return astArena.appendExpr(.objectLiteral(superTypes: superTypes, decl: declID, range: range))
    }

    func parseCallableReference(receiver: ExprID? = nil, receiverTypeRef: TypeRefID? = nil) -> ExprID? {
        guard let opToken = consume() else {
            return nil
        }
        guard let memberToken = current(),
              let memberName = tokenText(memberToken)
        else {
            diagnostics?.error(
                "KSWIFTK-PARSE-0014",
                "Expected an identifier after '::'.",
                range: opToken.range
            )
            return nil
        }
        _ = consume()
        let range = SourceRange(
            start: receiver.flatMap { astArena.exprRange($0)?.start } ?? opToken.range.start,
            end: memberToken.range.end
        )
        let reference = astArena.appendExpr(.callableRef(receiver: receiver, member: memberName, range: range))
        if let receiverTypeRef {
            astArena.setCallableRefReceiverTypeRef(reference, typeRef: receiverTypeRef)
        }
        return reference
    }

    /// Consumes tokens up to and including a closing brace matching a
    /// just-consumed opening `{` (depth starts at 1). Returns the tokens
    /// strictly between the braces, the end location reached, and whether
    /// the depth actually returned to 0 before the token stream ran out.
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
    /// literal rather than a block. Looks ahead (without consuming) at the brace
    /// group starting at the current `{` and reports whether it opens with a
    /// lambda parameter list followed by `->`.
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
    }

    private func parseLambdaParams(from tokens: [Token]) -> [LambdaParam] {
        let normalized = stripEnclosingParentheses(from: tokens)
        guard !normalized.isEmpty else {
            return []
        }

        var segments: [[Token]] = []
        var currentSegment: [Token] = []
        var depth = BuildASTPhase.BracketDepth()
        for token in normalized {
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
        for segment in segments {
            guard let nameIndex = segment.firstIndex(where: { token in
                switch token.kind {
                case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                    true
                default:
                    false
                }
            }), let name = lambdaParameterName(from: segment[nameIndex]) else {
                continue
            }
            params.append(LambdaParam(
                name: name,
                typeRef: parseLambdaParamTypeAnnotation(in: segment, after: nameIndex)
            ))
        }
        return params
    }

    /// Parses the `: Type` annotation of a lambda parameter segment, if present.
    private func parseLambdaParamTypeAnnotation(in segment: [Token], after nameIndex: Int) -> TypeRefID? {
        let colonIndex = nameIndex + 1
        guard colonIndex < segment.count, segment[colonIndex].kind == .symbol(.colon) else {
            return nil
        }
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
        return TypeRefParserCore.parseTypeRefPrefix(
            segment[(colonIndex + 1)...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics,
            recursionDepth: recursionDepth
        )?.ref
    }

    private func stripEnclosingParentheses(from tokens: [Token]) -> [Token] {
        guard tokens.count >= 2,
              tokens.first?.kind == .symbol(.lParen),
              tokens.last?.kind == .symbol(.rParen)
        else {
            return tokens
        }

        var depth = 0
        for (idx, token) in tokens.enumerated() {
            switch token.kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0, idx != tokens.count - 1 {
                    return tokens
                }
            default:
                break
            }
        }
        return Array(tokens.dropFirst().dropLast())
    }

    /// Checks whether paramTokens form a `(name, name, ...)` destructuring pattern.
    /// Returns the extracted names (nil for underscore), or nil when not destructuring.
    private func extractDestructuringNames(from paramTokens: [Token]) -> [InternedString?]? {
        let innerTokens = stripEnclosingParentheses(from: paramTokens)
        guard innerTokens.count != paramTokens.count else { return nil }
        let names = parseDestructuringNames(from: innerTokens)
        return names.count >= 2 ? names : nil
    }

    private func parseDestructuringNames(from innerTokens: [Token]) -> [InternedString?] {
        var names: [InternedString?] = []
        var idx = 0
        while idx < innerTokens.count {
            let token = innerTokens[idx]
            switch token.kind {
            case .symbol(.comma):
                idx += 1
                continue
            case .identifier, .backtickedIdentifier, .keyword, .softKeyword:
                guard let name = lambdaParameterName(from: token) else {
                    idx += 1
                    continue
                }
                let nameStr = interner.resolve(name)
                names.append(nameStr == "_" ? nil : name)
                idx += 1
            default:
                idx = skipTypeAnnotationIfPresent(innerTokens, from: idx)
            }
        }
        return names
    }

    private func skipTypeAnnotationIfPresent(_ tokens: [Token], from startIdx: Int) -> Int {
        var idx = startIdx
        guard idx < tokens.count, tokens[idx].kind == .symbol(.colon) else {
            return idx + 1
        }
        idx += 1
        var typeDepth = BuildASTPhase.BracketDepth()
        while idx < tokens.count {
            let current = tokens[idx]
            if typeDepth.isAtTopLevel, current.kind == .symbol(.comma) { break }
            typeDepth.track(current.kind)
            idx += 1
        }
        return idx
    }

    private func buildDestructuringLambda(
        names: [InternedString?],
        bodySlice: ArraySlice<Token>,
        fallbackStart: SourceLocation,
        range: SourceRange,
        label: InternedString?
    ) -> ExprID {
        let parsedBody = parseLambdaBody(bodySlice: bodySlice, fallbackStart: fallbackStart)
        let syntheticParam = interner.intern("__destructured_0")
        let nameRefExpr = astArena.appendExpr(.nameRef(syntheticParam, range))
        let destructuringExpr = astArena.appendExpr(.destructuringDecl(
            names: names, isMutable: false, initializer: nameRefExpr, range: range
        ))
        let wrappedBody = astArena.appendExpr(.blockExpr(
            statements: [destructuringExpr], trailingExpr: parsedBody, range: range
        ))
        return astArena.appendExpr(.lambdaLiteral(
            params: [syntheticParam], body: wrappedBody, label: label, range: range
        ))
    }

    /// Whether `tokens` (everything before a top-level `->` inside `{ ... }`)
    /// form a well-formed lambda parameter list: either empty (`{ -> body }`),
    /// a single destructuring group `(a, b)`, or a comma-separated list of
    /// `[annotations] name [: Type]` segments whose type parses completely
    /// (function types included). A body expression like `s as (Int) -> Int`
    /// leaves an `->` in the brace group; the strict check keeps it from being
    /// mistaken for `s as (Int)` parameters — `{ s as () -> Int }` is a lambda
    /// whose body casts `s`, and `if (c) { s as () -> Int }` is a plain block.
    private func isWellFormedLambdaParameterList(_ tokens: ArraySlice<Token>) -> Bool {
        if tokens.isEmpty { return true }
        let params = Array(tokens)
        if extractDestructuringNames(from: params) != nil { return true }
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
        if segment[idx].kind == .symbol(.lParen) {
            // Destructuring parameter `(a, b)` — kotlinc allows it mixed with
            // regular parameters — optionally followed by `: Type`.
            var parenDepth = 0
            var closeIndex: Int?
            for i in idx..<segment.endIndex {
                switch segment[i].kind {
                case .symbol(.lParen):
                    parenDepth += 1
                case .symbol(.rParen):
                    parenDepth -= 1
                    if parenDepth == 0 { closeIndex = i }
                default:
                    break
                }
                if closeIndex != nil { break }
            }
            guard let closeIndex,
                  isDestructuringEntries(segment[(idx + 1)..<closeIndex])
            else {
                return false
            }
            idx = closeIndex + 1
        } else {
            guard lambdaParameterName(from: segment[idx]) != nil else {
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

    /// Whether `inner` (the tokens between the parens of a destructuring
    /// parameter) are a comma-separated list of entry names (`a, _, c`).
    private func isDestructuringEntries(_ inner: ArraySlice<Token>) -> Bool {
        var expectName = true
        var sawComma = false
        for token in inner {
            if expectName {
                guard lambdaParameterName(from: token) != nil else {
                    return false
                }
                expectName = false
            } else {
                guard token.kind == .symbol(.comma) else {
                    return false
                }
                expectName = true
                sawComma = true
            }
        }
        return sawComma && !expectName
    }

    private func lambdaParameterName(from token: Token) -> InternedString? {
        switch token.kind {
        case let .identifier(name), let .backtickedIdentifier(name):
            name
        case let .keyword(keyword):
            interner.intern(keyword.rawValue)
        case let .softKeyword(keyword):
            interner.intern(keyword.rawValue)
        default:
            nil
        }
    }
}
