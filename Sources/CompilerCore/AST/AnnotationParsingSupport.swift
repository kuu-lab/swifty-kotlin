import Foundation

import RuntimeABI

enum AnnotationParsingSupport {
    struct ParsedAnnotation {
        let annotation: AnnotationNode
        let nextIndex: Int
        let invalidUseSiteTargetRange: SourceRange?
    }

    static func parseAnnotation(
        from tokens: [Token],
        start: Int,
        interner: StringInterner,
        allowUseSiteTarget: Bool,
        typeContext: Bool = false
    ) -> ParsedAnnotation? {
        guard start < tokens.count, tokens[start].kind == .symbol(.at) else {
            return nil
        }

        var index = start + 1
        guard index < tokens.count else {
            return nil
        }

        var useSiteTarget: String?
        var invalidUseSiteTargetRange: SourceRange?
        if index + 1 < tokens.count, tokens[index + 1].kind == .symbol(.colon),
           let candidateName = tokenText(tokens[index], interner: interner),
           SoftKeyword.useSiteTargetNames.contains(candidateName)
        {
            if allowUseSiteTarget {
                useSiteTarget = candidateName
            } else {
                invalidUseSiteTargetRange = tokens[index].range
            }
            index += 2
        }

        guard index < tokens.count else {
            return nil
        }

        let constructionStart = index
        guard var name = tokenText(tokens[index], interner: interner) else {
            return nil
        }
        index += 1
        while index + 1 < tokens.count,
              tokens[index].kind == .symbol(.dot),
              let nextPart = tokenText(tokens[index + 1], interner: interner)
        {
            name += "."
            name += nextPart
            index += 2
        }

        if let typeArgumentsEnd = endOfTypeArguments(in: tokens, at: index) {
            index = typeArgumentsEnd
        }

        var arguments: [String] = []
        if index < tokens.count, tokens[index].kind == .symbol(.lParen),
           consumesArgumentList(in: tokens, at: index, typeContext: typeContext)
        {
            index += 1
            var depth = BuildASTPhase.BracketDepth()
            depth.paren = 1
            var currentArg = ""
            var currentArgTokens: [Token] = []
            while index < tokens.count, depth.paren > 0 {
                let argToken = tokens[index]
                if argToken.kind == .symbol(.comma), depth.paren == 1,
                   depth.bracket == 0, depth.brace == 0
                {
                    let trimmed = currentArg.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        arguments.append(foldStringLiteralConcatenation(currentArgTokens, interner: interner) ?? trimmed)
                    }
                    currentArg = ""
                    currentArgTokens = []
                } else {
                    depth.track(argToken.kind)
                    if argToken.kind == .symbol(.rParen), depth.paren == 0 {
                        let trimmed = currentArg.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            arguments.append(foldStringLiteralConcatenation(currentArgTokens, interner: interner) ?? trimmed)
                        }
                    } else if let text = tokenText(argToken, interner: interner) {
                        currentArgTokens.append(argToken)
                        currentArg += text
                    } else {
                        currentArgTokens.append(argToken)
                        currentArg += tokenRawText(argToken, interner: interner)
                    }
                }
                index += 1
            }
        }

        return ParsedAnnotation(
            annotation: AnnotationNode(
                name: name,
                arguments: arguments,
                useSiteTarget: useSiteTarget,
                constructionTokens: Array(tokens[constructionStart..<index])
            ),
            nextIndex: index,
            invalidUseSiteTargetRange: invalidUseSiteTargetRange
        )
    }

    static func endOfTypeArguments(in tokens: [Token], at start: Int) -> Int? {
        guard start < tokens.count, tokens[start].kind == .symbol(.lessThan) else {
            return nil
        }
        var angleDepth = 0
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var templateDepth = 0
        var index = start
        while index < tokens.count {
            let kind = tokens[index].kind
            let inExpressionGroup = parenDepth > 0 || bracketDepth > 0 || braceDepth > 0 || templateDepth > 0
            if !inExpressionGroup {
                if kind == .symbol(.lessThan) {
                    angleDepth += 1
                } else if kind == .symbol(.greaterThan) {
                    angleDepth -= 1
                    if angleDepth == 0 {
                        return index + 1
                    }
                }
            }
            switch kind {
            case .symbol(.lParen): parenDepth += 1
            case .symbol(.rParen): parenDepth = max(0, parenDepth - 1)
            case .symbol(.lBracket): bracketDepth += 1
            case .symbol(.rBracket): bracketDepth = max(0, bracketDepth - 1)
            case .symbol(.lBrace): braceDepth += 1
            case .symbol(.rBrace): braceDepth = max(0, braceDepth - 1)
            case .templateExprStart: templateDepth += 1
            case .templateExprEnd: templateDepth = max(0, templateDepth - 1)
            default: break
            }
            index += 1
        }
        return nil
    }

    static func constructionArgumentListStart(in tokens: [Token], name: String) -> Int? {
        var index = min(qualifiedNameTokenCount(for: name), tokens.count)
        if let typeArgumentsEnd = endOfTypeArguments(in: tokens, at: index) {
            index = typeArgumentsEnd
        }
        guard index < tokens.count, tokens[index].kind == .symbol(.lParen) else {
            return nil
        }
        return index
    }

    static func qualifiedNameTokenCount(for name: String) -> Int {
        max(name.split(separator: ".").count * 2 - 1, 0)
    }

    /// Decides whether a `(` following an annotation name opens its argument
    /// list or the parameter list of the function type the annotation applies
    /// to (`typealias F = @Composable (navigator: Navigator) -> Unit`).
    /// Outside type position a `(` is always the argument list.
    ///
    /// kotlinc first parses `(...)` as the argument list and, only when that
    /// ends abnormally — a `)` directly followed by `->`, or contents that
    /// cannot be an expression such as a function type — retries the
    /// annotation in a whitespace-significant mode. The `(` therefore opens
    /// the function type's parameter list or a parenthesized type group only
    /// when whitespace or a comment precedes it: `@A (x: Int) -> Unit` and
    /// `@A (() -> Unit)?` annotate types while `@A(x: Int) -> Unit` and
    /// `@A(() -> Unit)?` keep the parentheses as arguments and error.
    ///
    /// A `->` inside the parentheses marks a parenthesized type group unless
    /// it is nested in `<>`, `{}`, `[]` or a string template, where it belongs
    /// to a type argument or an expression: the `->` in
    /// `@A (List<() -> Unit>)` keeps the group an argument list, matching
    /// kotlinc.
    private static func consumesArgumentList(
        in tokens: [Token], at lParenIndex: Int, typeContext: Bool
    ) -> Bool {
        guard typeContext else {
            return true
        }
        let innerIndex = lParenIndex + 1
        if innerIndex < tokens.count,
           tokens[innerIndex].kind == .keyword(.val)
               || tokens[innerIndex].kind == .keyword(.var)
        {
            return false
        }
        var depth = BuildASTPhase.BracketDepth()
        var hasFunctionTypeArrow = false
        for index in lParenIndex ..< tokens.count {
            let kind = tokens[index].kind
            if kind == .symbol(.arrow),
               depth.paren > 0,
               depth.angle == 0, depth.bracket == 0,
               depth.brace == 0, depth.template == 0
            {
                hasFunctionTypeArrow = true
            }
            depth.track(kind)
            if kind == .symbol(.rParen), depth.paren == 0 {
                if hasFunctionTypeArrow, !tokens[lParenIndex].leadingTrivia.isEmpty {
                    return false
                }
                let next = index + 1
                if next >= tokens.count || tokens[next].kind != .symbol(.arrow) {
                    return true
                }
                return tokens[lParenIndex].leadingTrivia.isEmpty
            }
        }
        return true
    }

    /// Keep folding token-based so empty operands and '+' inside string
    /// segments cannot be confused with concatenation syntax.
    private static func foldStringLiteralConcatenation(_ tokens: [Token], interner: StringInterner) -> String? {
        var index = 0
        var argumentPrefix = ""
        if tokens.count >= 2, tokens[1].kind == .symbol(.assign),
           let name = tokenText(tokens[0], interner: interner) {
            argumentPrefix = name + "="
            index = 2
        }
        var pieces: [String] = []
        while index < tokens.count {
            let opening = tokens[index].kind
            let isRaw: Bool
            switch opening {
            case .stringQuote, .multiDollarStringQuote:
                isRaw = false
            case .rawStringQuote, .multiDollarRawStringQuote:
                isRaw = true
            default:
                return nil
            }
            index += 1
            var segments: [String] = []
            while index < tokens.count, tokens[index].kind != opening {
                guard case let .stringSegment(segment) = tokens[index].kind else { return nil }
                let text = interner.resolve(segment)
                segments.append(isRaw ? KotlinStringSurrogateEncoding.encode(normalizeKotlinRawStringLineEndings(text)) : decodeKotlinStringEscapes(text))
                index += 1
            }
            guard index < tokens.count else { return nil }
            index += 1
            pieces.append(segments.joined())
            if index == tokens.count { break }
            guard tokens[index].kind == .symbol(.plus) else { return nil }
            index += 1
            guard index < tokens.count else { return nil }
        }
        guard pieces.count > 1 else { return nil }
        // A canonical regular literal keeps escapes and isolated UTF-16
        // surrogates lossless for metadata consumers and library roundtrips.
        let escaped = KotlinStringSurrogateEncoding.utf16CodeUnits(pieces.joined()).map { unit in
            let hex = String(unit, radix: 16)
            return "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
        }.joined()
        return argumentPrefix + "\"" + escaped + "\""
    }

    private static func tokenText(_ token: Token, interner: StringInterner) -> String? {
        switch token.kind {
        case let .identifier(interned):
            interner.resolve(interned)
        case let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        default:
            nil
        }
    }

    private static func tokenRawText(_ token: Token, interner: StringInterner) -> String {
        switch token.kind {
        case let .identifier(interned), let .backtickedIdentifier(interned):
            interner.resolve(interned)
        case let .keyword(keyword):
            keyword.rawValue
        case let .softKeyword(soft):
            soft.rawValue
        case let .stringSegment(interned):
            interner.resolve(interned)
        case .stringQuote:
            "\""
        case let .multiDollarStringQuote(dollarCount):
            // The lexer uses the same kind for both delimiters. Only the
            // opening token's source range includes the dollar prefix.
            (token.range.end.offset - token.range.start.offset > 1
                ? String(repeating: "$", count: dollarCount) : "") + "\""
        case let .multiDollarRawStringQuote(dollarCount):
            (token.range.end.offset - token.range.start.offset > 3
                ? String(repeating: "$", count: dollarCount) : "") + "\"\"\""
        case let .intLiteral(value):
            "\(value)"
        case let .longLiteral(value):
            "\(value)"
        case let .uintLiteral(value):
            "\(value)"
        case let .ulongLiteral(value):
            "\(value)"
        case let .floatLiteral(value):
            "\(value)"
        case let .doubleLiteral(value):
            "\(value)"
        case let .charLiteral(value):
            "'\(UnicodeScalar(value) ?? "?")'"
        case .rawStringQuote:
            "\"\"\""
        case .templateExprStart:
            String(repeating: "$", count: max(1, token.range.end.offset - token.range.start.offset - 1)) + "{"
        case .templateExprEnd:
            "}"
        case .templateSimpleNameStart:
            String(repeating: "$", count: max(1, token.range.end.offset - token.range.start.offset))
        case .eof:
            ""
        case let .missing(expected):
            "<missing:\(expected)>"
        case .symbol(let symbol):
            symbol.rawValue
        }
    }
}
