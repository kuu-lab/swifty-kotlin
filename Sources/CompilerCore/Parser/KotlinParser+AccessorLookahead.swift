extension KotlinParser {
    /// Used to absorb newline-separated accessor lines into the property
    /// declaration CST node.
    func isPropertyAccessorStart(allowsBodyless: Bool = true) -> Bool {
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
            // A bare `get`/`set` on the next line is the default accessor
            // spelling — after a member or top-level property it attaches
            // even without a modifier or annotation prefix (`var w = 1\nget`).
            // For a local property the same token is the next statement's
            // ordinary name (kotlinc reports `var x = 1\nget` inside a
            // function body as an unresolved reference), so only the legacy
            // `private set` spelling keeps attaching there.
            let isLegacyDefaultSetter = hasVisibilityModifier
                && stream.peek(offset).kind == .softKeyword(.set)
            guard allowsBodyless || isLegacyDefaultSetter else { return false }
            // A default accessor has no parameter list or body. Annotations
            // may precede either accessor, including `@JvmName(...) get` on
            // an expect property; keep it attached to that property.
            let afterAccessor = stream.peek(offset + 1)
            return afterAccessor.kind == .eof
                || afterAccessor.kind == .symbol(.semicolon)
                || afterAccessor.kind == .symbol(.rBrace)
                || hasLeadingNewline(afterAccessor)
        default:
            return false
        }
    }

    /// Whether the already-consumed property children contain an inline
    /// accessor header (`get() = x`, `set(v) { }`) — a `get`/`set` token
    /// immediately followed by `(` whose matching `)` leads into a body or
    /// return type. Member calls (`a.get()`, `get()` as an initializer
    /// expression) do not qualify, so `var x = get();\nset` still treats the
    /// `;`+newline as the end of the declaration.
    func propertyTailContainsAccessorHeader(_ children: [SyntaxChild]) -> Bool {
        var tokens: [Token] = []
        tokens.reserveCapacity(children.count)
        for child in children {
            guard case let .token(tokenID) = child,
                  let token = arena.token(tokenID)
            else {
                continue
            }
            tokens.append(token)
        }
        for (index, token) in tokens.enumerated() {
            switch token.kind {
            case .softKeyword(.get), .softKeyword(.set):
                break
            default:
                continue
            }
            if index > 0 {
                // `get`/`set` in call or expression position — member call,
                // initializer, argument list, or inside a lambda — is not an
                // accessor header, so `var x = get() {}` does not extend the
                // declaration the way `var x: Int get() = x` does.
                switch tokens[index - 1].kind {
                case .symbol(.dot), .symbol(.questionDot), .symbol(.doubleColon),
                     .symbol(.assign), .symbol(.comma), .symbol(.lParen),
                     .symbol(.lBrace), .symbol(.lBracket),
                     .keyword, .softKeyword:
                    continue
                default:
                    break
                }
            }
            guard index + 1 < tokens.count,
                  tokens[index + 1].kind == .symbol(.lParen)
            else {
                continue
            }
            var close = index + 1
            var depth = 0
            while close < tokens.count {
                if tokens[close].kind == .symbol(.lParen) { depth += 1 }
                if tokens[close].kind == .symbol(.rParen) {
                    depth -= 1
                    if depth == 0 { break }
                }
                close += 1
            }
            guard close < tokens.count, close + 1 < tokens.count else {
                continue
            }
            switch tokens[close + 1].kind {
            case .symbol(.assign), .symbol(.lBrace), .symbol(.colon):
                return true
            default:
                continue
            }
        }
        return false
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
