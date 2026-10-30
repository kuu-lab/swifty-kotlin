#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IfStatementSyntaxTests {
    @Test
    func incompleteElseIfWithoutConditionAndThenBranchIsRejected() {
        let parsed = parse("if (true) { } else if")
        let errors = parsed.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.map(\.code) == ["KSWIFTK-PARSE-0004", "KSWIFTK-PARSE-0004"])
        #expect(errors.map(\.message) == [
            "Expected parenthesized condition after 'if'.",
            "Expected then branch after 'if' condition.",
        ])
    }

    @Test
    func incompleteElseIfWithoutThenBranchIsRejected() {
        let parsed = parse("if (false) { } else if (true)")
        let errors = parsed.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(errors.map(\.code) == ["KSWIFTK-PARSE-0004"])
        #expect(errors.map(\.message) == ["Expected then branch after 'if' condition."])
    }

    @Test
    func completeElseIfChainRemainsAccepted() {
        let parsed = parse("if (true) { } else if (false) { } else { }")

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.filter { $0.kind == .ifExpr }.count == 2)
    }
}
#endif
