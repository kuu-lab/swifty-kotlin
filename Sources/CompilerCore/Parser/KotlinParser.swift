final class KotlinParser {
    static let maxNestingDepth = 128

    let stream: TokenStream
    let interner: StringInterner
    let diagnostics: DiagnosticEngine
    let arena: SyntaxArena
    var lastConsumedToken: Token?
    private var nestingDepth = 0
    private var nestingLimitReported = false
    var genuineDeclarationLookahead: [Int: Bool] = [:]
    var modifierDeclarationLookahead: [Int: Bool] = [:]

    init(tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
        stream = TokenStream(tokens)
        self.interner = interner
        self.diagnostics = diagnostics
        arena = SyntaxArena()
    }

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

        let skippedCount = LeanParser.recoverySkipCount(self, inBlock: inBlock, fromNestingLimit: true)
            ?? (stream.atEOF() ? 0 : 1)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        for _ in 0..<skippedCount {
            _ = consumeToken(into: &children, range: &range)
        }
        return arena.appendNode(kind: kind, range: range.value ?? start, children)
    }

    func parseFile() -> (arena: SyntaxArena, root: NodeID) {
        let file = FileAssembly(self)
        let end = LeanParser.parseFile(self, assembly: file)
        return (arena, file.finish(end))
    }

    final class FileAssembly {
        private let parser: KotlinParser
        private var children: [SyntaxChild] = []
        private var range = RangeAccumulator()
        private var pendingImports: [SyntaxChild] = []
        private var importRange = RangeAccumulator()
        private var pendingItem: (node: NodeID, start: SourceRange)?

        init(_ parser: KotlinParser) {
            self.parser = parser
        }

        var cursor: Int { parser.stream.index }

        func parseItem(_ dispatch: LeanParser.TopLevelDispatch) -> SyntaxNode? {
            guard pendingItem == nil else { return nil }
            let start = parser.stream.peek().range
            let node: NodeID
            switch dispatch {
            case .packageHeader: node = parser.parsePackageHeader()
            case .importHeader: node = parser.parseImportHeader()
            case .declaration: node = parser.parseDeclaration()
            case .statement: node = parseTopLevelStatement()
            case .eof: return nil
            }
            pendingItem = (node, start)
            return parser.arena.node(node)
        }

        func emitItem(_ action: LeanParser.FilePlacementAction, separators: Int) -> Int? {
            guard let item = pendingItem, separators <= parser.stream.tokens.count - cursor else { return nil }
            pendingItem = nil
            if action.lateImport {
                parser.diagnostics.error(
                    "KSWIFTK-PARSE-0017",
                    "Imports are only allowed in the beginning of file.",
                    range: item.start
                )
            }
            if action.flushImports {
                flushPendingImports()
            }
            let itemRange = parser.arena.node(item.node).range
            if action.appendImport {
                pendingImports.append(.node(item.node))
                importRange.append(itemRange)
            } else {
                children.append(.node(item.node))
            }
            range.append(itemRange)
            for _ in 0..<separators {
                _ = parser.consumeToken(into: &children, range: &range)
            }
            return cursor
        }

        func finish(_ action: LeanParser.FilePlacementAction) -> NodeID {
            if action.flushImports {
                flushPendingImports()
            }
            return parser.arena.appendNode(
                kind: action.rootKind, range: range.value ?? parser.invalidRange, children
            )
        }

        private func flushPendingImports() {
            let node = parser.arena.appendNode(
                kind: .importList, range: importRange.value ?? parser.invalidRange, pendingImports
            )
            children.append(.node(node))
            pendingImports.removeAll(keepingCapacity: true)
            importRange = RangeAccumulator()
        }

        private func parseTopLevelStatement() -> NodeID {
            let before = cursor
            let statement = parser.parseStatement(inBlock: false)
            guard let recovery = LeanParser.topLevelRecovery(parser, before: before) else { return statement }
            var skipped: [SyntaxChild] = []
            var skipRange = RangeAccumulator()
            parser.consumeSkippedTokens(recovery.skippedCount, into: &skipped, range: &skipRange)
            if recovery.forceAdvance {
                _ = parser.consumeToken(into: &skipped, range: &skipRange)
            }
            return parser.arena.appendNode(kind: .statement, range: skipRange.value ?? parser.invalidRange, skipped)
        }
    }
}
