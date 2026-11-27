#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        (TokenKind.eof, true, true),
        (.symbol(.rBrace), true, true),
        (.symbol(.at), false, true),
        (.keyword(.val), false, true),
        (.keyword(.fun), false, true),
        (.keyword(.object), false, true),
        (.keyword(.private), false, true),
        (.keyword(.enum), false, true),
        (.keyword(.import), false, true),
        (.keyword(.return), false, true),
        (.keyword(.companion), false, false),
        (.keyword(.throw), false, false),
        (.keyword(.else), false, false),
        (.softKeyword(.context), false, false),
        (.symbol(.semicolon), false, false),
        (.symbol(.lBrace), false, false),
    ])
    func statementStopContracts(kind: TokenKind, always: Bool, afterTopLevelNewline: Bool) {
        let lexed = lex("anchor")
        for inBlock in [false, true] {
            for newline in [false, true] {
                let token = Token(kind: kind, range: lexed.tokens[0].range, leadingTrivia: newline ? [.newline] : [])
                let expected = always || (!inBlock && newline && afterTopLevelNewline)
                #expect(LeanParser.shouldStopStatementBefore(
                    token, inBlock: inBlock, hasLeadingNewline: newline, diagnostics: lexed.diagnostics
                ) == expected)
            }
        }
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
