extension KotlinParser {
    func parseTypeArguments() -> NodeID {
        guard let result = LeanParser.scanTypeArguments(self) else {
            reportUnavailableLeanParser()
            return arena.appendNode(kind: .typeArgs, range: invalidRange, [])
        }
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        for _ in 0 ..< result.consumed {
            _ = consumeToken(into: &children, range: &range)
        }
        if result.unterminated {
            diagnostics.warning(
                "KSWIFTK-PARSE-0005",
                "Unterminated '<' type argument list.",
                range: stream.peek().rangeIfAvailable
            )
        }
        return arena.appendNode(kind: .typeArgs, range: range.value ?? invalidRange, children)
    }

    func canStartTypeArgumentsInternal(hasAnchorToken: Bool) -> Bool {
        guard let result = LeanParser.canStartTypeArguments(self, hasAnchorToken: hasAnchorToken) else {
            reportUnavailableLeanParser()
            return false
        }
        return result
    }

    func reportUnavailableLeanParser() {
        LeanParser.reportUnavailable(diagnostics, at: stream.peek().rangeIfAvailable)
    }
}
