extension KotlinLexer {
    func scanString(leadingTrivia: [TriviaPiece], start: Int) -> [Token] {
        let openStart = offset
        offset += 1
        var tokens: [Token] = []
        tokens.append(Token(kind: .stringQuote, range: makeRange(start: openStart, end: openStart + 1), leadingTrivia: leadingTrivia))
        var segmentStart = offset

        while offset < byteCount() {
            let ch = byte(at: offset)

            if ch == 0x22 {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                tokens.append(Token(kind: .stringQuote, range: makeRange(start: offset, end: offset + 1), leadingTrivia: []))
                offset += 1
                return tokens
            }

            if ch == 0x24, offset + 1 < byteCount(), byte(at: offset + 1) == 0x7B {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                let templateStart = offset
                offset += 2
                tokens.append(Token(kind: .templateExprStart, range: makeRange(start: templateStart, end: templateStart + 2), leadingTrivia: []))
                let templateExpr = scanTemplateExpression()
                tokens.append(contentsOf: templateExpr.tokens)
                tokens.append(Token(kind: .templateExprEnd, range: templateExpr.closeRange, leadingTrivia: []))
                segmentStart = offset
                continue
            }

            if ch == 0x24, offset + 1 < byteCount(), isIdentifierStart(byte(at: offset + 1)) {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                tokens.append(
                    Token(
                        kind: .templateSimpleNameStart,
                        range: makeRange(start: offset, end: offset + 1),
                        leadingTrivia: []
                    )
                )
                offset += 1
                if let templateName = scanTemplateName(leadingTrivia: [], start: offset) {
                    tokens.append(templateName)
                    segmentStart = offset
                    continue
                }
                segmentStart = offset
                continue
            }

            if ch == 0x5C {
                if !scanStringEscape(segmentStart: &segmentStart) {
                    break
                }
                continue
            }

            if ch == 0x0A {
                diagnostics.warning(
                    "KSWIFTK-LEX-0004",
                    "Unescaped line break in string literal.",
                    range: makeRange(start: offset, end: offset + 1)
                )
                offset += 1
                continue
            }

            if ch == 0x0D {
                diagnostics.warning(
                    "KSWIFTK-LEX-0004",
                    "Unescaped line break in string literal.",
                    range: makeRange(start: offset, end: offset + 1)
                )
                offset += 1
                continue
            }

            offset += 1
        }

        diagnostics.error(
            "KSWIFTK-LEX-0002",
            "Unterminated string literal.",
            range: makeRange(start: start, end: byteCount())
        )
        appendSegment(to: &tokens, from: segmentStart, to: byteCount(), leadingTrivia: [])
        return tokens
    }

    func scanRawString(leadingTrivia: [TriviaPiece], start: Int) -> [Token] {
        let quoteStart = offset
        offset += 3
        var tokens: [Token] = []
        tokens.append(
            Token(
                kind: .rawStringQuote,
                range: makeRange(start: quoteStart, end: quoteStart + 3),
                leadingTrivia: leadingTrivia
            )
        )

        var segmentStart = offset
        while offset + 2 < byteCount() {
            if starts(with: "\"\"\"", at: offset) {
                break
            }
            if byte(at: offset) == 0x24, offset + 1 < byteCount(), byte(at: offset + 1) == 0x7B {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                let templateStart = offset
                offset += 2
                tokens.append(Token(kind: .templateExprStart, range: makeRange(start: templateStart, end: templateStart + 2), leadingTrivia: []))
                let templateExpr = scanTemplateExpression()
                tokens.append(contentsOf: templateExpr.tokens)
                tokens.append(Token(kind: .templateExprEnd, range: templateExpr.closeRange, leadingTrivia: []))
                segmentStart = offset
                continue
            }
            offset += 1
        }

        if offset + 2 >= byteCount() {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated raw string literal.",
                range: makeRange(start: start, end: byteCount())
            )
            appendSegment(to: &tokens, from: segmentStart, to: byteCount(), leadingTrivia: [])
            return tokens
        }

        appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
        tokens.append(
            Token(
                kind: .rawStringQuote,
                range: makeRange(start: offset, end: offset + 3),
                leadingTrivia: []
            )
        )
        offset += 3
        return tokens
    }

    func scanTemplateExpression() -> (tokens: [Token], closeRange: SourceRange) {
        let expressionStart = offset
        var depth = 1
        var tokens: [Token] = []

        while offset < byteCount(), depth > 0 {
            let leadingTrivia = consumeTrivia()
            if offset >= byteCount() {
                break
            }

            if byte(at: offset) == 0x24, offset + 1 < byteCount(), byte(at: offset + 1) == 0x7B {
                let templateStart = offset
                let templateRange = makeRange(start: templateStart, end: templateStart + 2)
                offset += 2
                var nestedTokens: [Token] = []
                nestedTokens.append(Token(kind: .templateExprStart, range: templateRange, leadingTrivia: leadingTrivia))
                let nested = scanTemplateExpression()
                nestedTokens.append(contentsOf: nested.tokens)
                nestedTokens.append(Token(kind: .templateExprEnd, range: nested.closeRange, leadingTrivia: []))
                tokens.append(contentsOf: nestedTokens)
                continue
            }

            if byte(at: offset) == 0x22 {
                if starts(with: "\"\"\"", at: offset) {
                    tokens.append(contentsOf: scanRawString(leadingTrivia: leadingTrivia, start: offset))
                } else {
                    tokens.append(contentsOf: scanString(leadingTrivia: leadingTrivia, start: offset))
                }
                continue
            }

            if byte(at: offset) == 0x27 {
                tokens.append(scanCharLiteral(leadingTrivia: leadingTrivia, start: offset))
                continue
            }

            if byte(at: offset) == 0x7B {
                tokens.append(Token(
                    kind: .symbol(.lBrace),
                    range: makeRange(start: offset, end: offset + 1),
                    leadingTrivia: leadingTrivia
                ))
                offset += 1
                depth += 1
                continue
            }

            if byte(at: offset) == 0x7D {
                if depth == 1 {
                    let closeRange = makeRange(start: offset, end: offset + 1)
                    offset += 1
                    return (tokens, closeRange)
                }
                tokens.append(Token(
                    kind: .symbol(.rBrace),
                    range: makeRange(start: offset, end: offset + 1),
                    leadingTrivia: leadingTrivia
                ))
                offset += 1
                depth -= 1
                continue
            }

            let scanned = scanNextTokens(leadingTrivia: leadingTrivia)
            if scanned.isEmpty {
                diagnostics.error(
                    "KSWIFTK-LEX-0001",
                    "Invalid character in template expression.",
                    range: makeRange(start: offset, end: min(offset + 1, byteCount()))
                )
                offset += 1
                continue
            }
            for scannedToken in scanned {
                switch scannedToken.kind {
                case .symbol(.lBrace):
                    depth += 1
                case .symbol(.rBrace):
                    depth -= 1
                default:
                    break
                }
            }
            tokens.append(contentsOf: scanned)
            for token in scanned {
                switch token.kind {
                case .symbol(.lBrace):
                    depth += 1
                case .symbol(.rBrace):
                    if depth > 1 {
                        depth -= 1
                    }
                default:
                    break
                }
            }
        }

        diagnostics.error(
            "KSWIFTK-LEX-0002",
            "Unterminated template expression.",
            range: SourceRange(
                start: SourceLocation(file: file, offset: expressionStart),
                end: SourceLocation(file: file, offset: byteCount())
            )
        )
        return (tokens, SourceRange(
            start: SourceLocation(file: file, offset: expressionStart),
            end: SourceLocation(file: file, offset: byteCount())
        ))
    }

    // MARK: - Multi-dollar string support (Kotlin 2.1+)

    /// Scans a multi-dollar single-line string: `$$"..."`, `$$$"..."`, etc.
    /// The `dollarCount` is the number of `$` in the prefix (e.g. 2 for `$$`).
    /// Only `dollarCount` consecutive `$` followed by `{` triggers interpolation.
    /// Only `dollarCount` consecutive `$` followed by an identifier start triggers simple name interpolation.
    /// Fewer `$` are treated as literal text.
    func scanMultiDollarString(leadingTrivia: [TriviaPiece], start: Int, dollarCount: Int) -> [Token] {
        let openStart = offset
        // Skip the dollar prefix and opening quote
        offset += dollarCount + 1
        var tokens: [Token] = []
        tokens.append(
            Token(
                kind: .multiDollarStringQuote(dollarCount: dollarCount),
                range: makeRange(start: openStart, end: openStart + dollarCount + 1),
                leadingTrivia: leadingTrivia
            )
        )
        var segmentStart = offset

        while offset < byteCount() {
            let ch = byte(at: offset)

            // Closing quote
            if ch == 0x22 {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
                tokens.append(
                    Token(
                        kind: .multiDollarStringQuote(dollarCount: dollarCount),
                        range: makeRange(start: offset, end: offset + 1),
                        leadingTrivia: []
                    )
                )
                offset += 1
                return tokens
            }

            // Check for dollar sequences
            if ch == 0x24 {
                scanDollarInterpolation(dollarCount: dollarCount, segmentStart: &segmentStart, tokens: &tokens)
                continue
            }

            // Escape sequences (same as regular strings)
            if ch == 0x5C {
                if !scanStringEscape(segmentStart: &segmentStart) {
                    break
                }
                continue
            }

            if ch == 0x0A || ch == 0x0D {
                diagnostics.warning(
                    "KSWIFTK-LEX-0004",
                    "Unescaped line break in string literal.",
                    range: makeRange(start: offset, end: offset + 1)
                )
                offset += 1
                continue
            }

            offset += 1
        }

        diagnostics.error(
            "KSWIFTK-LEX-0002",
            "Unterminated string literal.",
            range: makeRange(start: start, end: byteCount())
        )
        appendSegment(to: &tokens, from: segmentStart, to: byteCount(), leadingTrivia: [])
        return tokens
    }

    /// Handles dollar interpolation logic for multi-dollar strings.
    /// Assumes the current character is a dollar sign.
    private func scanDollarInterpolation(dollarCount: Int, segmentStart: inout Int, tokens: inout [Token]) {
        let consecutiveDollars = countConsecutiveDollars(at: offset)
        let afterDollars = offset + consecutiveDollars

        // Expression interpolation: exactly dollarCount $ followed by {
        if consecutiveDollars >= dollarCount,
           afterDollars < byteCount(),
           byte(at: afterDollars) == 0x7B
        {
            // Emit any literal dollars before the interpolation threshold
            let literalDollars = consecutiveDollars - dollarCount
            if literalDollars > 0 {
                appendSegment(to: &tokens, from: segmentStart, to: offset + literalDollars, leadingTrivia: [])
            } else {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
            }
            let templateStart = offset + literalDollars
            offset = afterDollars + 1 // skip past $...${
            tokens.append(
                Token(
                    kind: .templateExprStart,
                    range: makeRange(start: templateStart, end: templateStart + dollarCount + 1),
                    leadingTrivia: []
                )
            )
            let templateExpr = scanTemplateExpression()
            tokens.append(contentsOf: templateExpr.tokens)
            tokens.append(Token(kind: .templateExprEnd, range: templateExpr.closeRange, leadingTrivia: []))
            segmentStart = offset
            return
        }

        // Simple name interpolation: exactly dollarCount $ followed by identifier start
        if consecutiveDollars >= dollarCount,
           afterDollars < byteCount(),
           isIdentifierStart(byte(at: afterDollars)),
           byte(at: afterDollars) != 0x24  // exclude '$' itself which is also identifier start
        {
            let literalDollars = consecutiveDollars - dollarCount
            if literalDollars > 0 {
                appendSegment(to: &tokens, from: segmentStart, to: offset + literalDollars, leadingTrivia: [])
            } else {
                appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
            }
            let templateStart = offset + literalDollars
            tokens.append(
                Token(
                    kind: .templateSimpleNameStart,
                    range: makeRange(start: templateStart, end: templateStart + dollarCount),
                    leadingTrivia: []
                )
            )
            offset = afterDollars
            if let templateName = scanTemplateName(leadingTrivia: [], start: offset) {
                tokens.append(templateName)
                segmentStart = offset
                return
            }
            segmentStart = offset
            return
        }

        // Not enough dollars for interpolation — treat all as literal
        offset += consecutiveDollars
    }

    @discardableResult
    private func scanStringEscape(segmentStart: inout Int) -> Bool {
        if offset + 1 >= byteCount() {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated string escape.",
                range: makeRange(start: offset, end: byteCount())
            )
            return false
        }
        let escaped = byte(at: offset + 1)
        if escaped == 0x75 {
            if let unicode = scanUnicodeEscape(escapeStart: offset + 1) {
                offset += 1 + unicode.length
                return true
            } else {
                let missingEnd = min(offset + 12, byteCount())
                diagnostics.error(
                    "KSWIFTK-LEX-0003",
                    "Invalid unicode escape sequence in string literal.",
                    range: makeRange(start: offset, end: missingEnd)
                )
                if offset + 6 <= byteCount() {
                    offset += 6
                } else {
                    offset += 2
                }
                segmentStart = offset
                return true
            }
        }
        if scalarValue(forEscape: escaped) == nil {
            diagnostics.error(
                "KSWIFTK-LEX-0003",
                "Invalid escape sequence in string literal.",
                range: makeRange(start: offset, end: min(offset + 2, byteCount()))
            )
            offset += 2
            segmentStart = offset
            return true
        }
        offset += 2
        return true
    }

    /// Scans a multi-dollar raw (triple-quoted) string: `$$"""..."""`, `$$$"""..."""`, etc.
    func scanMultiDollarRawString(leadingTrivia: [TriviaPiece], start: Int, dollarCount: Int) -> [Token] {
        let quoteStart = offset
        // Skip the dollar prefix and opening triple-quote
        offset += dollarCount + 3
        var tokens: [Token] = []
        tokens.append(
            Token(
                kind: .multiDollarRawStringQuote(dollarCount: dollarCount),
                range: makeRange(start: quoteStart, end: quoteStart + dollarCount + 3),
                leadingTrivia: leadingTrivia
            )
        )

        var segmentStart = offset
        while offset + 2 < byteCount() {
            if starts(with: "\"\"\"", at: offset) {
                break
            }

            if byte(at: offset) == 0x24 {
                scanDollarInterpolation(dollarCount: dollarCount, segmentStart: &segmentStart, tokens: &tokens)
                continue
            }

            offset += 1
        }

        if offset + 2 >= byteCount() {
            diagnostics.error(
                "KSWIFTK-LEX-0002",
                "Unterminated raw string literal.",
                range: makeRange(start: start, end: byteCount())
            )
            appendSegment(to: &tokens, from: segmentStart, to: byteCount(), leadingTrivia: [])
            return tokens
        }

        appendSegment(to: &tokens, from: segmentStart, to: offset, leadingTrivia: [])
        tokens.append(
            Token(
                kind: .multiDollarRawStringQuote(dollarCount: dollarCount),
                range: makeRange(start: offset, end: offset + 3),
                leadingTrivia: []
            )
        )
        offset += 3
        return tokens
    }

    func appendSegment(to tokens: inout [Token], from: Int, to: Int, leadingTrivia: [TriviaPiece]) {
        if from >= to {
            return
        }
        let segmentText = text(from: from ..< to)
        tokens.append(
            Token(
                kind: .stringSegment(interner.intern(segmentText)),
                range: makeRange(start: from, end: to),
                leadingTrivia: leadingTrivia
            )
        )
    }
}
