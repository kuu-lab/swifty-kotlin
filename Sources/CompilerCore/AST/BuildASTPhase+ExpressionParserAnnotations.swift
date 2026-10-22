extension BuildASTPhase.ExpressionParser {
    /// Shared by prefix-unary expressions and control-flow bodies, whose
    /// braces denote blocks unless they contain explicit lambda parameters.
    func parseAnnotatedExpression(_ parseOperand: () -> ExprID?) -> ExprID? {
        let remaining = Array(tokens[index...])
        var next = 0
        var annotations: [AnnotationNode] = []
        while next < remaining.count, remaining[next].kind == .symbol(.at) {
            guard let parsed = AnnotationParsingSupport.parseAnnotation(
                from: remaining, start: next, interner: interner, allowUseSiteTarget: false
            ), parsed.nextIndex > next else {
                diagnostics?.error(
                    "KSWIFTK-PARSE-0001",
                    "Expected annotation name after '@'.",
                    range: remaining[next].range
                )
                return nil
            }
            if let range = parsed.invalidUseSiteTargetRange {
                diagnostics?.error(
                    "KSWIFTK-PARSE-ANNOTATION-TARGET",
                    "Use-site targets are not allowed on expression annotations.",
                    range: range
                )
            }
            annotations.append(parsed.annotation)
            next = parsed.nextIndex
        }
        guard !annotations.isEmpty else { return nil }
        index += next
        guard let operand = parseOperand() else { return nil }
        astArena.prependExpressionAnnotations(annotations, for: operand)
        return operand
    }
}
