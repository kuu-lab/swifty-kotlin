import Foundation
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ConstructorNameCallTests {
    private func check(_ source: String) throws -> CompilationContext {
        let input = "/virtual/constructor-name.kt"
        let context = makeCompilationContext(inputs: [input], includeStdlib: false)
        _ = context.sourceManager.addFile(path: input, contents: Data(source.utf8))
        try runSema(context)
        return context
    }

    @Test(arguments: [
        "fun main() { constructor() }",
        "fun main() { @Suppress(\"x\") constructor() }",
        "fun main() { val x = 1; constructor() }",
        "fun main() {\nconstructor()\n}",
        "class C { fun f() { constructor() } }",
        "class C { init { constructor() } }",
        "class C { constructor() { constructor() } }",
        "fun main() { if (true) { constructor() } }",
        "fun main() { val f = { constructor() } }",
        "fun main() { fun local() { constructor() }; local() }",
    ])
    func unresolvedConstructorNameIsRejected(source: String) throws {
        let context = try check(source)
        #expect(context.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.message.contains("constructor")
        }, "\(source): \(context.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun constructor(): Int = 7\nfun main() { constructor(); constructor() }",
        "fun main() { fun constructor(): Int = 7\nconstructor() }",
        "fun main() { val constructor: () -> Int = { 7 }; constructor() }",
        "class C { fun constructor(): Int = 7; fun f() { constructor() } }",
        "class C(val x: Int) { constructor() : this(7); fun f() { constructor() } }\nfun constructor() {}",
        "fun `constructor`(): Int = 7\nfun main() { `constructor`() }",
    ])
    func declaredConstructorNameIsAccepted(source: String) throws {
        let context = try check(source)
        #expect(!context.diagnostics.hasError, "\(source): \(context.diagnostics.diagnostics)")
    }

    @Test(arguments: ["", "@Suppress(\"x\") "])
    func constructorCallsAndFollowingStatementsRemainInFunctionBody(prefix: String) throws {
        let (ast, context) = try buildASTModule(from: """
        fun constructor(): Int = 7
        fun main() { \(prefix)constructor(); constructor(); 42 }
        """, includeStdlib: false)
        let main = try #require(firstFunDecl(named: "main", in: ast, interner: context.interner))
        guard case let .block(expressions, _) = main.body else {
            Issue.record("Expected main block")
            return
        }
        #expect(expressions.count == 3)
        for expression in expressions.prefix(2) {
            guard case let .call(callee, _, _, _) = ast.arena.expr(expression),
                  case let .nameRef(name, _) = ast.arena.expr(callee)
            else {
                Issue.record("Expected a constructor name call")
                continue
            }
            #expect(context.interner.resolve(name) == "constructor")
        }
        if !prefix.isEmpty, let first = expressions.first {
            #expect(ast.arena.expressionAnnotations(for: first).map(\.name) == ["Suppress"])
        }
    }
}
