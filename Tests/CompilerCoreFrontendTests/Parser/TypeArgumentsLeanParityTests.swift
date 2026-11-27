#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("<T>", true), ("<Map<K, V>>", true), ("<T,>", true), ("<in T>", true), ("<T", true),
        ("<>", false), ("<T,, U>", false), ("<in>", false), ("<T, out>", false), ("Plain", false)
    ])
    func declarationTypeArgumentStart(source: String, accepts: Bool) {
        let lexed = lex("anchor " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()

        #expect(parser.canStartTypeArgumentsInternal(hasAnchorToken: true) == accepts)
        #expect(!parser.canStartTypeArgumentsInternal(hasAnchorToken: false))
        #expect(parser.stream.index == 1)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test(arguments: ["<Map<K>> tail", "<T(fn(a > b))> tail", "<T[x > y]> tail", "<T{a > b}> tail", "<T"])
    func typeArgumentOffsetPreservesExpressionGroups(source: String) {
        let lexed = lex("anchor skip " + source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()

        let end = parser.offsetPastTypeArguments(from: 1)
        #expect(parser.stream.peek(end) == lexed.tokens[source.hasSuffix("tail") ? lexed.tokens.count - 2 : lexed.tokens.count - 1])
        #expect(parser.stream.index == 1)
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    @Test
    func deeplyNestedTypeArgumentConsumptionKeepsFollowingToken() {
        let nesting = 10_000
        let source = String(repeating: "< ", count: nesting) + "T " + String(repeating: "> ", count: nesting) + "tail"
        let lexed = lex(source)
        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)

        let node = parser.parseTypeArguments()

        #expect(parser.arena.node(node).kind == .typeArgs)
        #expect(parser.stream.index == nesting * 2 + 1)
        #expect(parser.stream.peek() == lexed.tokens[lexed.tokens.count - 2])
        #expect(parser.diagnostics.diagnostics.isEmpty)
    }

    private static let oraclePath = ProcessInfo.processInfo.environment["KSWIFTK_TYPE_ARGUMENTS_ORACLE"]

    private enum Stop: String, Decodable {
        case missingOpen
        case closed
        case recovery
        case eof
    }

    private struct OracleCase: Decodable {
        let source: String
        let tokenCount: Int
        let consumed: Int
        let stop: Stop
    }

    @Test(.enabled(if: oraclePath != nil))
    func matchesLeanOracle() throws {
        let path = try #require(Self.oraclePath)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let cases = try JSONDecoder().decode([OracleCase].self, from: data)
        try #require(cases.count == 791)
        for oracleCase in cases {
            try compareWithSwift(oracleCase)
        }
        print("Compared \(cases.count) Lean oracle cases with the compiler's bundled Lean parser.")
    }

    private func compareWithSwift(_ oracleCase: OracleCase) throws {
        let lexed = lex("class Box" + oracleCase.source)
        let source = Comment(rawValue: oracleCase.source.debugDescription)
        try #require(lexed.diagnostics.diagnostics.isEmpty, source)

        let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
        _ = parser.stream.advance()
        _ = parser.stream.advance()
        let start = parser.stream.index
        let expectedEnd = start + oracleCase.consumed
        try #require(lexed.tokens.count - start == oracleCase.tokenCount, source)
        try #require(lexed.tokens.indices.contains(expectedEnd), source)

        let node = parser.parseTypeArguments()
        let diagnostics = lexed.diagnostics.diagnostics
        try #require(!diagnostics.contains { $0.code == "KSWIFTK-PARSE-0032" }, source)
        let stop: Stop
        if diagnostics.isEmpty {
            stop = parser.stream.index == start ? .missingOpen : .closed
        } else {
            #expect(diagnostics.map(\.code) == ["KSWIFTK-PARSE-0005"], source)
            #expect(diagnostics.map(\.severity) == [.warning], source)
            stop = parser.stream.atEOF() ? .eof : .recovery
        }

        #expect(stop == oracleCase.stop, source)
        #expect(parser.stream.index == expectedEnd, source)
        #expect(parser.stream.peek() == lexed.tokens[expectedEnd], source)
        #expect(parser.arena.node(node).kind == .typeArgs, source)
        #expect(parser.arena.tokens == Array(lexed.tokens[start ..< expectedEnd]), source)
        if oracleCase.stop == .recovery {
            #expect(diagnostics.first?.primaryRange == lexed.tokens[expectedEnd].range, source)
        }
    }
}
#endif
