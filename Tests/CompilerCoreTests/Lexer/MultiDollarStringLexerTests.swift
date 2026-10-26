#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MultiDollarStringLexerTests {
    @Test
    func regularMultiDollarStringsSupportEmptyAndSimpleNameTemplates() {
        let source = #"""
        val empty = $$""
        val two = $$"$$x"
        val four = $$$$"$$$$x"
        val eight = $$$$$$$$"$$$$$$$$x"
        """#
        let result = lex(source)

        #expect(!result.diagnostics.hasError)
        #expect(result.tokens.filter { $0.kind == .templateSimpleNameStart }.count == 3)
        #expect(result.tokens.compactMap { token -> String? in
            guard case let .identifier(name) = token.kind else { return nil }
            return result.interner.resolve(name)
        } == ["empty", "two", "x", "four", "x", "eight", "x"])
        #expect(result.tokens.compactMap { token -> Int? in
            guard case let .multiDollarStringQuote(dollarCount) = token.kind else { return nil }
            return dollarCount
        } == [2, 2, 2, 2, 4, 4, 8, 8])
    }
}
#endif
