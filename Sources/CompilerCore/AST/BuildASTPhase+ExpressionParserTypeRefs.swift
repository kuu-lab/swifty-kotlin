
extension BuildASTPhase.ExpressionParser {
    func tryParseCallableReferenceTypeReceiver(from startIndex: Int) -> (expr: ExprID, typeRef: TypeRefID)? {
        guard let parsed = TypeRefParserCore.parseTypeRefPrefix(
            tokens[startIndex...],
            interner: interner,
            astArena: astArena,
            options: .declaration,
            recursionDepth: recursionDepth
        ),
            case let .named(path, _, _) = astArena.typeRef(parsed.ref),
            let name = path.last,
            startIndex + parsed.consumed < tokens.endIndex,
            tokens[startIndex + parsed.consumed].kind == .symbol(.doubleColon)
        else {
            return nil
        }
        index = startIndex + parsed.consumed
        let range = SourceRange(start: tokens[startIndex].range.start, end: tokens[index - 1].range.end)
        let receiver = astArena.appendExpr(.nameRef(name, range))
        return (receiver, parsed.ref)
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
