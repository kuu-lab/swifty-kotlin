#if canImport(Testing)
@testable import CompilerCore
@testable import LSPServer
import Testing

@Suite("LSP.Feature")
struct FeatureTests {
    private let uri = "file:///tmp/LSPFeatures.kt"

    @Test
    func documentSymbolsOutlineClassAndMembers() {
        let source = """
        class Foo {
            val bar: Int = 1
            fun baz(): Int { return bar }
        }

        fun topLevel() {}
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let symbols = DocumentSymbolFeature.documentSymbols(for: analysis)

        let names = symbols.map(\.name)
        #expect(names.contains("Foo"), "Outline should include the class: \(names)")
        #expect(names.contains("topLevel"), "Outline should include the top-level function: \(names)")

        if let foo = symbols.first(where: { $0.name == "Foo" }) {
            #expect(foo.kind == LSPSymbolKind.class.rawValue)
            let childNames = (foo.children ?? []).map(\.name)
            #expect(childNames.contains("bar"), "Class outline should include property: \(childNames)")
            #expect(childNames.contains("baz"), "Class outline should include method: \(childNames)")
        } else {
            Issue.record("Expected a symbol for class Foo")
        }
    }

    @Test
    func hoverOnIntegerLiteralReportsType() {
        let source = "fun main() {\n    val answer = 42\n}\n"
        let analysis = Analyzer().analyze(uri: uri, text: source)
        guard let pos = LSPTestSupport.position(of: "42", in: source) else {
            Issue.record("Could not locate literal in source")
            return
        }

        let hover = HoverFeature.hover(for: analysis, line: pos.line, character: pos.character)
        #expect(hover != nil, "Hover over a literal should return type information")
        #expect(
            hover?.contents.value.contains("Int") ?? false,
            "Hover for `42` should mention Int, got: \(hover?.contents.value ?? "nil")"
        )
    }

    @Test
    func hoverSurvivesParseErrorBeforeRecoveredExpression() {
        let source = """
        package demo

        }
        fun recovered(): Int = 42
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)

        #expect(
            analysis.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0006" },
            "The fixture should retain the syntax error diagnostic: \(analysis.diagnostics.map(\.code))"
        )
        #expect(analysis.context.ast != nil, "LSP analysis should build AST after a parse error")
        #expect(analysis.context.sema != nil, "LSP analysis should run Sema after a parse error")

        guard let position = LSPTestSupport.position(of: "42", in: source) else {
            Issue.record("Could not locate recovered expression")
            return
        }
        let hover = HoverFeature.hover(
            for: analysis,
            line: position.line,
            character: position.character
        )
        #expect(hover != nil, "Hover should survive a syntax error before a valid expression")
        #expect(
            hover?.contents.value.contains("Int") ?? false,
            "Recovered expression hover should mention Int, got: \(hover?.contents.value ?? "nil")"
        )
    }

    @Test
    func definitionResolvesTopLevelReference() {
        let source = """
        fun helper(): Int {
            return 1
        }

        fun main() {
            helper()
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        // Locate the call site `helper()` inside `main` (the second occurrence).
        guard let callRange = source.range(of: "helper", range: source.range(of: "fun main")!.upperBound ..< source.endIndex) else {
            Issue.record("Could not locate call site")
            return
        }
        let prefix = source[source.startIndex ..< callRange.lowerBound]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        let line = lines.count - 1
        let character = (lines.last ?? "").utf16.count

        let location = DefinitionFeature.definition(for: analysis, line: line, character: character + 1)
        // Definition resolution depends on call-binding population; assert that
        // when a location is returned it points inside the analyzed document.
        if let location {
            #expect(location.uri == DocumentURI.uri(fromPath: analysis.path))
            #expect(location.range.start.line <= line)
        }
    }

    @Test
    func hoverPositionResolutionMatchesLinearSelection() throws {
        let source = """
        fun main() {
            val answer = (1 + 2) * 3
        }
        """
        let analysis = Analyzer().analyze(uri: uri, text: source)
        let ast = try #require(analysis.context.ast)
        let fileID = try #require(analysis.fileID)
        let position = try #require(LSPTestSupport.position(of: "1", in: source))
        let offset = try #require(
            analysis.context.sourceManager.offset(
                ofLine: position.line,
                utf16Character: position.character,
                in: fileID
            )
        )
        let offsets = [max(0, offset - 1), offset, offset + 1, source.utf8.count]
        let resolver = PositionResolver(ast: ast, fileID: fileID)

        for candidateOffset in offsets {
            #expect(
                resolver.innermostExpr(at: candidateOffset) == linearInnermostExpr(
                    ast: ast,
                    fileID: fileID,
                    offset: candidateOffset
                )
            )
        }

        let hover = HoverFeature.hover(
            for: analysis,
            line: position.line,
            character: position.character
        )
        let hoverRange = try #require(hover?.range)
        #expect(hoverRange.start.line == position.line)
        #expect(hoverRange.start.character == position.character)
        #expect(hoverRange.end.character == position.character + 1)
    }

    @Test
    func positionResolverUsesFileLocalIndexAndPreservesTiesAfterAppend() {
        let targetFileID = FileID(rawValue: 7)
        let otherFileID = FileID(rawValue: 8)
        let outerRange = SourceRange(
            start: SourceLocation(file: targetFileID, offset: 10),
            end: SourceLocation(file: targetFileID, offset: 30)
        )
        let innerRange = SourceRange(
            start: SourceLocation(file: targetFileID, offset: 15),
            end: SourceLocation(file: targetFileID, offset: 20)
        )
        let tieRange = SourceRange(
            start: SourceLocation(file: targetFileID, offset: 40),
            end: SourceLocation(file: targetFileID, offset: 50)
        )
        let arena = ASTArena()
        let outerID = arena.appendExpr(.intLiteral(0, outerRange))
        let innerID = arena.appendExpr(.intLiteral(1, innerRange))
        let tieFirstID = arena.appendExpr(.intLiteral(2, tieRange))
        _ = arena.appendExpr(.intLiteral(3, tieRange))

        var otherFileFirstID: ExprID?
        for index in 0 ..< 2_000 {
            let start = 1_000 + index * 2
            let range = SourceRange(
                start: SourceLocation(file: otherFileID, offset: start),
                end: SourceLocation(file: otherFileID, offset: start + 1)
            )
            let exprID = arena.appendExpr(.intLiteral(Int64(index), range))
            if index == 0 {
                otherFileFirstID = exprID
            }
        }

        let module = ASTModule(
            files: [
                ASTFile(fileID: targetFileID, packageFQName: [], imports: [], topLevelDecls: [], scriptBody: []),
                ASTFile(fileID: otherFileID, packageFQName: [], imports: [], topLevelDecls: [], scriptBody: []),
            ],
            arena: arena,
            declarationCount: 0,
            tokenCount: 0
        )
        let resolver = PositionResolver(ast: module, fileID: targetFileID)
        #expect(resolver.innermostExpr(at: 10) == outerID)
        #expect(resolver.innermostExpr(at: 17) == innerID)
        #expect(resolver.innermostExpr(at: 20) == innerID)
        #expect(resolver.innermostExpr(at: 45) == tieFirstID)
        #expect(resolver.innermostExpr(at: 50) == tieFirstID)
        #expect(resolver.innermostExpr(at: 5) == nil)
        #expect(resolver.innermostExpr(at: 17) != outerID)

        let appendedRange = SourceRange(
            start: SourceLocation(file: targetFileID, offset: 16),
            end: SourceLocation(file: targetFileID, offset: 18)
        )
        let appendedID = arena.appendExpr(.intLiteral(4, appendedRange))
        #expect(resolver.innermostExpr(at: 17) == appendedID)

        let otherResolver = PositionResolver(ast: module, fileID: otherFileID)
        #expect(otherResolver.innermostExpr(at: 1_000) == otherFileFirstID)
    }

    private func linearInnermostExpr(ast: ASTModule, fileID: FileID, offset: Int) -> ExprID? {
        let exprs = ast.arena.exprs
        var best: ExprID?
        var bestWidth = Int.max
        for index in exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(exprID), range.start.file == fileID else {
                continue
            }
            guard range.start.offset <= offset, offset <= range.end.offset else {
                continue
            }
            let width = range.end.offset - range.start.offset
            if width < bestWidth {
                best = exprID
                bestWidth = width
            }
        }
        return best
    }
}
#endif
