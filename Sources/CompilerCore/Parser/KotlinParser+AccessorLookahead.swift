extension KotlinParser {
    /// Returns `true` when `token` looks like the start of a property accessor
    /// (`get()` or `set(...)` followed by `=` or `{`). Used to absorb
    /// newline-separated accessor lines into the property declaration CST node.
    func isPropertyAccessorStart(_ token: Token) -> Bool {
        var offset = 0
        var hasVisibilityModifier = false
        // Skip annotations without consuming them: an annotation on the next
        // declaration must not be absorbed into the preceding property.
        while stream.peek(offset).kind == .symbol(.at) {
            offset += 1
            if isAnnotationUseSiteTarget(stream.peek(offset)),
               stream.peek(offset + 1).kind == .symbol(.colon) {
                offset += 2
            }
            guard isIdentifierLike(stream.peek(offset).kind) else { return false }
            offset += 1
            while stream.peek(offset).kind == .symbol(.dot),
                  isIdentifierLike(stream.peek(offset + 1).kind) {
                offset += 2
            }
            if stream.peek(offset).kind == .symbol(.lParen) {
                offset = offsetPastBalancedGroup(from: offset, open: .symbol(.lParen), close: .symbol(.rParen))
            }
        }
        visibilityPrefix: while true {
            guard case let .keyword(keyword) = stream.peek(offset).kind else { break }
            switch keyword {
            case .public, .private, .internal, .protected:
                hasVisibilityModifier = true
                offset += 1
            case .inline:
                offset += 1
            default:
                break visibilityPrefix
            }
        }
        switch stream.peek(offset).kind {
        case .softKeyword(.get), .softKeyword(.set):
            if isAccessorHeaderFollowedByBody(at: offset) {
                return true
            }
            guard hasVisibilityModifier,
                  stream.peek(offset).kind == .softKeyword(.set)
            else {
                return false
            }
            let afterSetter = stream.peek(offset + 1)
            return afterSetter.kind == .eof
                || afterSetter.kind == .symbol(.semicolon)
                || afterSetter.kind == .symbol(.rBrace)
                || hasLeadingNewline(afterSetter)
        default:
            return false
        }
    }

    /// Returns `true` when the current token is the `field` soft keyword
    /// followed by `=` or `:`, indicating an explicit backing field declaration
    /// (Kotlin 2.0 feature).  Example: `field = ""` or `field: String = ""`.
    func isExplicitBackingFieldStart(_ token: Token) -> Bool {
        guard case .softKeyword(.field) = token.kind else { return false }
        let next = stream.peek(1)
        switch next.kind {
        case .symbol(.assign), .symbol(.colon):
            return true
        default:
            return false
        }
    }

    /// Checks whether the tokens starting at `stream.peek(1)` form a
    /// well-formed accessor header `(...)` followed by `=` or `{`.
    private func isAccessorHeaderFollowedByBody(at start: Int) -> Bool {
        guard stream.peek(start + 1).kind == .symbol(.lParen) else {
            return false
        }
        var offset = start + 1
        var parenDepth = 0
        let maxLookahead = start + 64
        while offset <= maxLookahead {
            let nextToken = stream.peek(offset)
            switch nextToken.kind {
            case .symbol(.lParen):
                parenDepth += 1
            case .symbol(.rParen):
                parenDepth -= 1
                if parenDepth == 0 {
                    return isAccessorBodyStart(stream.peek(offset + 1))
                }
            default:
                break
            }
            if parenDepth < 0 { return false }
            offset += 1
        }
        return false
    }

    /// Returns `true` when the given token can begin an accessor body (`=` or `{`).
    private func isAccessorBodyStart(_ token: Token) -> Bool {
        switch token.kind {
        case .symbol(.assign), .symbol(.lBrace):
            true
        default:
            false
        }
    }
}
