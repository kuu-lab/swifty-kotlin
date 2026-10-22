extension KotlinParser {
    /// Used to absorb newline-separated accessor lines into the property
    /// declaration CST node.
    func isPropertyAccessorStart(_ token: Token) -> Bool {
        var offset = 0
        var hasVisibilityModifier = false
        // Skip annotations without consuming them: an annotation on the next
        // declaration must not be absorbed into the preceding property.
        while stream.peek(offset).kind == .symbol(.at) {
            guard let end = offsetPastAnnotationPrefix(from: offset) else { return false }
            offset = end
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

    /// Explicit backing field declaration (Kotlin 2.0 feature):
    /// `field = ""` or `field: String = ""`.
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
                    return accessorBodyStart(after: offset + 1, through: maxLookahead) != nil
                }
            default:
                break
            }
            if parenDepth < 0 { return false }
            offset += 1
        }
        return false
    }

    private func accessorBodyStart(after headerEnd: Int, through limit: Int) -> Int? {
        guard stream.peek(headerEnd).kind == .symbol(.colon) else {
            return isAccessorBodyStart(stream.peek(headerEnd)) ? headerEnd : nil
        }

        var offset = headerEnd + 1
        var typeDepth = BracketDepth()
        var sawTypeToken = false
        while offset <= limit {
            let token = stream.peek(offset)
            guard token.kind != .eof else { return nil }

            let atTypeTopLevel = typeDepth.isTopLevel && typeDepth.angle == 0
            if atTypeTopLevel {
                switch token.kind {
                case .symbol(.assign), .symbol(.lBrace):
                    // `get(): = x` has no type after the colon; absorb it as an
                    // accessor anyway so the AST builder can diagnose the
                    // missing return type instead of losing the header to a
                    // `get(...)` expression parse.
                    return offset
                case .symbol(.semicolon), .symbol(.rBrace):
                    return nil
                default:
                    break
                }
                if sawTypeToken, hasLeadingNewline(token), startsGenuineDeclaration(at: offset) {
                    return nil
                }
            }

            typeDepth.track(token.kind)
            sawTypeToken = true
            offset += 1
        }
        return nil
    }

    private func isAccessorBodyStart(_ token: Token) -> Bool {
        switch token.kind {
        case .symbol(.assign), .symbol(.lBrace):
            true
        default:
            false
        }
    }
}
