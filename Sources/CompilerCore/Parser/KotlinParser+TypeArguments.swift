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
            if depth == 1, hasLeadingNewline(next), isLikelyTopLevelDeclarationStart(next) {
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
        guard hasAnchorToken else { return false }
        guard case .symbol(.lessThan) = stream.peek().kind else { return false }

        var depth = 1
        var projectionExpected = true
        var sawProjection = false

        var lookahead = 1
        while true {
            let token = stream.peek(lookahead)
            switch token.kind {
            case .eof:
                return depth == 1 && sawProjection && !projectionExpected
            case .symbol(.lessThan):
                depth += 1
            case .symbol(.greaterThan):
                depth -= 1
                if depth == 0 {
                    // Every caller sits at a declaration-header position
                    // (after a `class`/`interface`/`enum class`/`typealias`
                    // name or the `fun`/`val`/`var` keyword), where `<…>`
                    // can only be a type-parameter list: no infix
                    // comparison is possible, so any token may follow `>`.
                    // In particular a bodiless generic class may be followed
                    // by a hard keyword such as `fun` or `val` starting the
                    // next declaration.
                    return !projectionExpected
                }
            case .symbol(.comma):
                if depth == 1 {
                    if !sawProjection { return false }
                    projectionExpected = true
                }
            case .identifier, .backtickedIdentifier:
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                }
            case .symbol(.star):
                if depth == 1 {
                    sawProjection = true
                    projectionExpected = false
                }
            case .keyword(.in), .softKeyword(.out):
                if depth == 1, projectionExpected {
                    break
                }
                if depth == 1 {
                    projectionExpected = true
                }
            case .symbol(.dot), .symbol(.question), .symbol(.questionDot),
                 .symbol(.doubleColon), .symbol(.colon):
                if depth == 1, projectionExpected {
                    return false
                }
            default:
                if depth == 0 {
                    return false
                }
            }
            lookahead += 1
        }
    }

}
