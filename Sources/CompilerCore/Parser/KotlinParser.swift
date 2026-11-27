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

        let recoveryStartIndex = stream.index
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        while !stream.atEOF(), !isSynchronizationPoint(stream.peek(), inBlock: inBlock) {
            _ = consumeToken(into: &children, range: &range)
        }
        if stream.index == recoveryStartIndex, !stream.atEOF() {
            _ = consumeToken(into: &children, range: &range)
        }
        return arena.appendNode(kind: kind, range: range.value ?? start, children)
    }

    func parseFile() -> (arena: SyntaxArena, root: NodeID) {
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        var sawTopLevelStatement = false
        var sawFileBody = false
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

        func parseTopLevelStatement() -> NodeID {
            let before = stream.index
            var statement = parseStatement(inBlock: false)
            if stream.index == before {
                var skipChildren: [SyntaxChild] = []
                var skipRange = RangeAccumulator()
                skipToSynchronizationPoint(inBlock: false, into: &skipChildren, range: &skipRange)
                if stream.index == before, !stream.atEOF() {
                    _ = consumeToken(into: &skipChildren, range: &skipRange)
                }
                statement = arena.appendNode(kind: .statement, range: skipRange.value ?? invalidRange, skipChildren)
            }
            sawTopLevelStatement = true
            return statement
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
            case _ where isDeclarationStart(token.kind):
                if case .softKeyword(.context) = token.kind {
                    switch declarationPrefixVerdict(at: 0) {
                    case .declaration:
                        node = parseDeclaration()
                    case .notDeclaration, .overBudget:
                        node = parseTopLevelStatement()
                    }
                } else if isAmbiguousDeclarationPrefix(token),
                          declarationPrefixVerdict(at: 0) == .overBudget {
                    node = parseTopLevelStatement()
                } else {
                    node = parseDeclaration()
                }
            default:
                node = parseTopLevelStatement()
            }

            let nodeKind = arena.node(node).kind
            if nodeKind == .importHeader {
                if sawFileBody {
                    diagnostics.error(
                        "KSWIFTK-PARSE-0017",
                        "Imports are only allowed in the beginning of file.",
                        range: token.range
                    )
                }
                pendingImports.append(.node(node))
                importRange.append(arena.node(node).range)
                range.append(arena.node(node).range)
                continue
            }
            if nodeKind != .packageHeader {
                sawFileBody = true
            }

            flushPendingImportsIfNeeded()

            children.append(.node(node))
            range.append(arena.node(node).range)

            // Braced declarations can leave their separator unconsumed.
            // Treating it as a statement would incorrectly select script mode.
            while stream.peek().kind == .symbol(.semicolon) {
                _ = consumeToken(into: &children, range: &range)
            }
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
            for _ in 0..<recovery.skippedCount {
                _ = parser.consumeToken(into: &skipped, range: &skipRange)
            }
            if recovery.forceAdvance {
                _ = parser.consumeToken(into: &skipped, range: &skipRange)
            }
            return parser.arena.appendNode(kind: .statement, range: skipRange.value ?? parser.invalidRange, skipped)
        }
    }
}
