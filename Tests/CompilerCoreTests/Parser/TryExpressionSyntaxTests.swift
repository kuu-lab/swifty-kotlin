#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TryExpressionSyntaxTests {
    @Test(arguments: [
        "fun main() { println(try { 5 }) }",
        "fun main() { try { println(\"t\") } }",
        "fun main() { println(try { \"s\" as? Int } .let { it }) }",
        "fun main() { val value = try { 5 } }",
        "val value = try { 5 }",
        "fun value() = try { 5 }",
        "fun main() { val f = { try { 5 } } }",
        "fun main() { try { try { 5 } } finally { } }",
    ])
    func missingHandlerReportsOnce(_ source: String) throws {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0015" }
        #expect(errors.count == 1)
        let error = try #require(errors.first)
        #expect(error.severity == .error)
        #expect(error.message == "Expected 'catch' or 'finally' after 'try' block.")
        let range = try #require(error.primaryRange)
        #expect(String(decoding: Array(source.utf8)[range.start.offset ..< range.end.offset], as: UTF8.self) == "try")
    }

    @Test(arguments: [
        "try { 5 } catch (e: Exception) { 6 }",
        "try { 5 } finally { }",
        "try { 5 } catch (e: Exception) { 6 } finally { }",
        "try { 5 }\ncatch (e: Exception) { 6 }\ncatch (e: Throwable) { 7 }",
        "try { 5 }\nfinally { }",
        "(try { 5 } finally { }).let { it }",
    ])
    func validHandlersRemainAccepted(_ expression: String) throws {
        let ctx = makeContextFromSource("fun main() { println(\(expression)) }")
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        #expect(ast.arena.exprs.contains { if case .tryExpr = $0 { true } else { false } })
    }

    @Test
    func syntaxRecoveryPreservesFollowingDeclaration() {
        let source = "try { 5 }\nfun after() = 7"
        let parsed = parse(source)
        #expect(parsed.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-PARSE-0015" }.count == 1)
        #expect(parsed.arena.nodes.filter { $0.kind == .funDecl }.count == 1)
    }
}
#endif
