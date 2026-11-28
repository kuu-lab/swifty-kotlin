#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        "fun next()", "object Next {}", "class Next", "interface Next", "val next = 1",
        "var next = 1", "typealias Next = Int",
    ])
    func annotationArgumentRecoveryLeavesNextDeclaration(declaration: String) throws {
        let lexed = lex("@Tag(1\n" + declaration)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(.annotations, into: &children, range: &range)
        let boundary = 4
        let missing = try #require(parser.arena.tokens.last)
        #expect(parser.stream.index == boundary)
        #expect(parser.stream.peek() == lexed.tokens[boundary])
        #expect(Array(parser.arena.tokens.dropLast()) == Array(lexed.tokens.prefix(boundary)))
        #expect(missing.kind == .missing(expected: .symbol(.rParen)))
        #expect(missing.range.start == lexed.tokens[boundary].range.start)
        #expect(missing.range.end == missing.range.start)
        #expect(children.count == boundary + 1)
        #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0001"])
        #expect(parser.diagnostics.diagnostics.first?.primaryRange == missing.range)
    }

    @Test(arguments: [
        "@Tag(\nfun () {})", "@Tag(\nobject : T {})", "@Tag(\nobject {})",
        "@Tag(x::\nclass Name)", "@Tag([\nfun nested()])", "@Tag(1",
    ])
    func annotationArgumentsKeepNestedContentAndLeaveEOF(source: String) {
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(.annotations, into: &children, range: &range)
        #expect(parser.stream.atEOF())
        #expect(parser.arena.tokens == Array(lexed.tokens.dropLast()))
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func consumingAnnotationArgumentsHandlesNestingBeyondTheLookaheadBudget() {
        let depth = KotlinParser.declarationLookaheadWorkLimit
        let source = "@Tag(" + String(repeating: "[", count: depth) + "1"
            + String(repeating: "]", count: depth) + "\nfun next()"
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        var children: [SyntaxChild] = []
        var range = RangeAccumulator()
        parser.consumeLeadingPrefix(.annotations, into: &children, range: &range)
        #expect(parser.stream.index == 4 + 2 * depth)
        #expect(parser.stream.peek().kind == .keyword(.fun))
        #expect(parser.arena.tokens.last?.kind == .missing(expected: .symbol(.rParen)))
        #expect(parser.diagnostics.diagnostics.map(\.code) == ["KSWIFTK-PARSE-0001"])
    }
}
#endif
