import Foundation

import RuntimeABI

enum AnnotationParsingSupport {
    struct ParsedAnnotation {
        let annotation: AnnotationNode
        let nextIndex: Int
        let invalidUseSiteTargetRange: SourceRange?
    }

    /// - Parameter typeContext: Pass `true` when parsing an annotation in
    ///   type position (`val x: @A () -> Unit`, `typealias F = @A (T) -> R`).
    ///   Mirrors kotlinc's TYPE_CONTEXT rule: a `(` after the annotation name
    ///   opens the argument list unless the token inside is `val`/`var`, or —
    ///   only when whitespace or a comment precedes it — its matching `)` is
    ///   followed by `->`. In those cases it is the parameter list of the
    ///   function type being annotated.
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

    /// Decides whether a `(` following an annotation name opens its argument
    /// list or the parameter list of the function type the annotation applies
    /// to (`typealias F = @Composable (navigator: Navigator) -> Unit`).
    /// Outside type position a `(` is always the argument list.
    ///
    /// kotlinc first parses `(...)` as the argument list and, only when that
    /// ends abnormally — a `)` directly followed by `->` — retries the
    /// annotation in a whitespace-significant mode. The `(` therefore opens
    /// the function type's parameter list only when whitespace or a comment
    /// precedes it: `@A (x: Int) -> Unit` annotates a function type while
    /// `@A(x: Int) -> Unit` keeps `(x: Int)` as arguments and errors on the
    /// dangling `->`.
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
        var depth = 0
        for index in lParenIndex ..< tokens.count {
            switch tokens[index].kind {
            case .symbol(.lParen):
                depth += 1
            case .symbol(.rParen):
                depth -= 1
                if depth == 0 {
                    let next = index + 1
                    if next >= tokens.count || tokens[next].kind != .symbol(.arrow) {
                        return true
                    }
                    return tokens[lParenIndex].leadingTrivia.isEmpty
                }
            default:
                break
            }
        }
        // An unbalanced `(` cannot start a function type; treat it as the
        // argument list so diagnostics land on the unclosed annotation.
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
                segments.append(isRaw ? KotlinStringSurrogateEncoding.encode(text) : decodeKotlinStringEscapes(text))
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
