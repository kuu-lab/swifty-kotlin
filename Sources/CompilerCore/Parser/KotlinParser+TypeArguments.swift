extension KotlinParser {
    func parseTypeArguments() -> NodeID {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var depth = 1

        guard consumeIfSymbol(.lessThan, into: &children, range: &range) else {
            return arena.appendNode(
                kind: .typeArgs,
                range: range.value ?? invalidRange,
                []
            )
        }

        while !stream.atEOF(), depth > 0 {
            let next = stream.peek()
            if depth == 1, hasLeadingNewline(next), isLikelyTopLevelDeclarationStart(next),
               !continuesAngleBracketListAtNewlineAnnotation(next) {
                break
            }

            let token = consumeToken(into: &children, range: &range)
            if token.kind == .eof {
                break
            }

            switch token.kind {
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    return arena.appendNode(kind: .typeArgs, range: range.value ?? invalidRange, children)
                }
            default:
                break
            }
        }

        diagnostics.warning(
            "KSWIFTK-PARSE-0005",
            "Unterminated '<' type argument list.",
            range: stream.peek().rangeIfAvailable
        )
        return arena.appendNode(
            kind: .typeArgs,
            range: range.value ?? invalidRange,
            children
        )
    }

    func canStartTypeArgumentsInternal(hasAnchorToken: Bool) -> Bool {
        LeanParser.canStartTypeArguments(self, hasAnchorToken: hasAnchorToken)
    }
}
