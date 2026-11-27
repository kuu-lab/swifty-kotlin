#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension TypeArgumentsLeanParityTests {
    @Test(arguments: [
        ("fun f() {};;", false, 2),
        ("class C {};;\nfun f() {}", false, 2),
        ("package p;;;", false, 2),
        ("fun f() {};;\nprintln(1)", true, 2),
        ("import p;;", true, 0),
    ])
    func separatorTokensPreserveFileClassification(source: String, script: Bool, rawSemicolons: Int) {
        let parsed = parse(source)
        let separators = parsed.arena.children(of: parsed.root).count { child in
            guard case let .token(id) = child else { return false }
            return parsed.arena.token(id)?.kind == .symbol(.semicolon)
        }
        #expect(separators == rawSemicolons)
        #expect(parsed.arena.node(parsed.root).kind == (script ? .script : .kotlinFile))
        #expect(!parsed.arena.tokens.contains { $0.kind == .eof })
        #expect(parsed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
