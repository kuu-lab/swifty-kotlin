final class KotlinParser {
    /// Caps active recursive parser productions across blocks, statements, and
    /// declarations. The budget is shared because those productions call one
    /// another to parse nested control flow and declaration bodies.
    static let maxNestingDepth = 128

    let stream: TokenStream
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let arena: SyntaxArena
    var lastConsumedToken: Token?
    private var nestingDepth = 0
    private var nestingLimitReported = false

    init(tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
        stream = TokenStream(tokens)
        self.interner = interner
        self.diagnostics = diagnostics
        arena = SyntaxArena()
    }

    /// Enters one recursive grammar production. The caller must pair success
    /// with `leaveNesting()` using `defer`.
    func enterNesting() -> Bool {
        nestingDepth += 1
        guard nestingDepth <= Self.maxNestingDepth else {
            nestingDepth -= 1
            return false
        }
        return true
    }

    func leaveNesting() {
        nestingDepth -= 1
    }

    /// Produces a partial node and iteratively skips to the next parser
    /// synchronization point after the shared nesting budget is exhausted.
    func recoverFromNestingLimit(inBlock: Bool, kind: SyntaxKind = .statement) -> NodeID {
        let start = stream.peek().range
        if !nestingLimitReported {
            nestingLimitReported = true
            diagnostics.error(
                "KSWIFTK-PARSE-0013",
                "Structured syntax nesting exceeds the maximum supported depth of \(Self.maxNestingDepth).",
                range: start
            )
        }

        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        while !stream.atEOF(), !isSynchronizationPoint(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
        if children.isEmpty, !stream.atEOF(), !isSynchronizationPoint(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
        return arena.appendNode(kind: kind, range: range.value ?? start, children)
    }

    func parseFile() -> (arena: SyntaxArena, root: NodeID) {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var sawTopLevelStatement = false
        // Scripts (kotlinc -script / .kts) allow any declaration kind at top
        // level alongside bare statements, but never a `package` declaration.
        var sawPackageHeader = false

        var pendingImports: [SyntaxChild] = []
        var importRange = RangeAccumulator()
        func flushPendingImportsIfNeeded() {
            guard !pendingImports.isEmpty else {
                return
            }
            let importListNode = arena.appendNode(
                kind: .importList,
                range: importRange.value ?? invalidRange,
                pendingImports
            )
            children.append(.node(importListNode))
            pendingImports.removeAll(keepingCapacity: true)
            importRange = RangeAccumulator()
        }

        while !stream.atEOF() {
            let token = stream.peek()
            if token.kind == .eof {
                break
            }

            var node: NodeID
            switch token.kind {
            case .keyword(.package):
                node = parsePackageHeader()
                sawPackageHeader = true
            case .keyword(.import):
                node = parseImportHeader()
                pendingImports.append(.node(node))
                importRange.append(arena.node(node).range)
                range.append(arena.node(node).range)
                continue
            case _ where isDeclarationStart(token.kind):
                node = parseDeclaration()
            case .softKeyword(.context):
                node = parseDeclaration()
            default:
                let before = stream.index
                node = parseStatement(inBlock: false)
                if stream.index == before {
                    var skipChildren: [SyntaxChild] = []
                    var skipRange = RangeAccumulator()
                    skipToSynchronizationPoint(inBlock: false, into: &skipChildren, range: &skipRange)
                    if stream.index == before, !stream.atEOF() {
                        _ = consumeToken(into: &skipChildren, range: &skipRange)
                    }
                    node = arena.appendNode(kind: .statement, range: skipRange.value ?? invalidRange, skipChildren)
                }
                sawTopLevelStatement = true
            }

            flushPendingImportsIfNeeded()

            children.append(.node(node))
            range.append(arena.node(node).range)
        }

        flushPendingImportsIfNeeded()

        let rootKind: SyntaxKind = if sawTopLevelStatement, !sawPackageHeader {
            .script
        } else {
            .kotlinFile
        }

        return (
            arena: arena,
            root: arena.appendNode(
                kind: rootKind,
                range: range.value ?? invalidRange, children
            )
        )
    }
}
