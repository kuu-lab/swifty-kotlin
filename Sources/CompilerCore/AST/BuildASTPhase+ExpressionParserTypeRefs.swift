
extension BuildASTPhase.ExpressionParser {
    /// Recognizes a parenthesized function type immediately followed by `::`.
    /// The scan avoids speculative TypeRefParserCore calls that would leave
    /// unused type refs on ordinary parenthesized expressions.
    func looksLikeFunctionTypeCallableReferenceReceiver(from startIndex: Int) -> Bool {
        guard startIndex < tokens.endIndex,
              tokens[startIndex].kind == .symbol(.lParen)
        else {
            return false
        }

        var parenthesisDepth = 0
        var braceDepth = 0
        var typeArgumentDepth = 0
        var hasFunctionArrow = false
        var cursor = startIndex
        while cursor < tokens.endIndex {
            switch tokens[cursor].kind {
            case .symbol(.lParen):
                parenthesisDepth += 1
            case .symbol(.rParen):
                parenthesisDepth -= 1
                if parenthesisDepth == 0 {
                    var separatorIndex = cursor + 1
                    if separatorIndex < tokens.endIndex,
                       tokens[separatorIndex].kind == .symbol(.question)
                    {
                        separatorIndex += 1
                    }
                    return hasFunctionArrow
                        && separatorIndex < tokens.endIndex
                        && tokens[separatorIndex].kind == .symbol(.doubleColon)
                }
                if parenthesisDepth < 0 { return false }
            case .symbol(.lBrace):
                braceDepth += 1
            case .symbol(.rBrace):
                braceDepth = max(0, braceDepth - 1)
            case .symbol(.lessThan):
                if braceDepth == 0 { typeArgumentDepth += 1 }
            case .symbol(.greaterThan):
                if typeArgumentDepth > 0 { typeArgumentDepth -= 1 }
            case .symbol(.arrow):
                if braceDepth == 0, typeArgumentDepth == 0 { hasFunctionArrow = true }
            default:
                break
            }
            cursor += 1
        }
        return false
    }

    func tryParseCallableReferenceTypeReceiver(
        from startIndex: Int,
        functionTypeOnly: Bool = false
    ) -> (expr: ExprID?, typeRef: TypeRefID, range: SourceRange)? {
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[startIndex...],
            interner: interner,
            astArena: astArena,
            options: .declaration,
            recursionDepth: recursionDepth
        ),
            let typeRef = astArena.typeRef(parsed.ref),
            startIndex + parsed.consumed < tokens.endIndex,
            tokens[startIndex + parsed.consumed].kind == .symbol(.doubleColon),
            // The `::` must lie at or ahead of the parser's current position.
            // A `::` behind `index` was already folded into the expression
            // (e.g. the `::class` in `T::class.findAssociatedObject<A>()`), so
            // re-walking it would rewind `index` and loop forever.
            startIndex + parsed.consumed >= index
        else {
            return nil
        }
        if functionTypeOnly {
            guard case .functionType = typeRef else { return nil }
        }
        let endIndex = startIndex + parsed.consumed
        let range = SourceRange(start: tokens[startIndex].range.start, end: tokens[endIndex - 1].range.end)
        let receiver: ExprID?
        switch typeRef {
        case let .named(path, _, _):
            guard let name = path.last else { return nil }
            receiver = astArena.appendExpr(.nameRef(name, range))
        case .functionType:
            // Function types do not have a classifier name to put in the
            // receiver expression. The type ref itself carries the receiver
            // and lets Sema resolve extensions on it.
            receiver = nil
        default:
            return nil
        }
        index = endIndex
        return (receiver, parsed.ref, range)
    }

    func parseTypeReference(_ fallbackRange: SourceRange, allowFunctionType: Bool = false) -> TypeRefID? {
        _ = fallbackRange
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = allowFunctionType
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[index...],
            interner: interner,
            astArena: astArena,
            options: options,
            diagnostics: diagnostics,
            recursionDepth: recursionDepth
        ) else {
            return nil
        }
        index += parsed.consumed
        return parsed.ref
    }

    func tryParseExplicitTypeArgs() -> [TypeRefID]? {
        guard matches(.symbol(.lessThan)) else { return nil }
        let savedIndex = index
        var options = TypeRefParserCore.Options.expressionInline
        options.allowFunctionType = true
        _ = consume()
        var refs: [TypeRefID] = []
        while true {
            guard let token = current() else {
                index = savedIndex
                return nil
            }
            if token.kind == .symbol(.greaterThan) {
                if refs.isEmpty {
                    index = savedIndex
                    return nil
                }
                _ = consume()
                return refs
            }
            if !refs.isEmpty {
                guard consumeIf(.symbol(.comma)) != nil else {
                    index = savedIndex
                    return nil
                }
            }
            guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
                tokens[index...],
                interner: interner,
                astArena: astArena,
                options: options,
                diagnostics: diagnostics,
                recursionDepth: recursionDepth
            ) else {
                index = savedIndex
                return nil
            }
            index += parsed.consumed
            refs.append(parsed.ref)
        }
    }

}
