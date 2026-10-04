import Foundation

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
        allowUseSiteTarget: Bool
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
        if index < tokens.count, tokens[index].kind == .symbol(.lParen) {
            index += 1
            var depth = BuildASTPhase.BracketDepth()
            depth.paren = 1
            var currentArg = ""
            while index < tokens.count, depth.paren > 0 {
                let argToken = tokens[index]
                if argToken.kind == .symbol(.comma), depth.paren == 1,
                   depth.bracket == 0, depth.brace == 0
                {
                    let trimmed = currentArg.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        arguments.append(trimmed)
                    }
                    currentArg = ""
                } else {
                    depth.track(argToken.kind)
                    if argToken.kind == .symbol(.rParen), depth.paren == 0 {
                        let trimmed = currentArg.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            arguments.append(trimmed)
                        }
                    } else if let text = tokenText(argToken, interner: interner) {
                        currentArg += text
                    } else {
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
                useSiteTarget: useSiteTarget
            ),
            nextIndex: index,
            invalidUseSiteTargetRange: invalidUseSiteTargetRange
        )
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
            "\"\(interner.resolve(interned))\""
        case .stringQuote:
            "\""
        case let .multiDollarStringQuote(dollarCount):
            String(repeating: "$", count: dollarCount) + "\""
        case let .multiDollarRawStringQuote(dollarCount):
            String(repeating: "$", count: dollarCount) + "\"\"\""
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
            "${"
        case .templateExprEnd:
            "}"
        case .templateSimpleNameStart:
            "$"
        case .eof:
            ""
        case let .missing(expected):
            "<missing:\(expected)>"
        case .symbol(let symbol):
            symbol.rawValue
        }
    }
}
