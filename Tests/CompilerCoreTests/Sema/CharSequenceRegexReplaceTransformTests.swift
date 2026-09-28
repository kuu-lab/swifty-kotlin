@testable import CompilerCore
import Testing

@Suite
struct CharSequenceRegexReplaceTransformTests {
    private let sourcePath = "__bundled_kotlin/text/StringHOF.kt"

    @Test
    func implicitItResolvesFromTransformParameter() throws {
        let source = #"""
        fun replaceMatches(): String {
            val regex = Regex("b")
            return "abcb".replace(regex) { it.value }
        }
        """#
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let diagnostics = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(!ctx.diagnostics.hasError, "Expected implicit `it` to resolve, got: \(diagnostics)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let replaceCall = try #require(ast.arena.exprs.indices.first { index in
            let id = ExprID(rawValue: Int32(index))
            guard case let .memberCall(_, callee, _, _, _) = ast.arena.expr(id) else {
                return false
            }
            return ctx.interner.resolve(callee) == "replace"
        }.map { ExprID(rawValue: Int32($0)) })
        let binding = try #require(sema.bindings.callBinding(for: replaceCall))
        let sourceFile = try #require(sema.symbols.sourceFileID(for: binding.chosenCallee))
        #expect(ctx.sourceManager.path(of: sourceFile) == sourcePath)
    }
}
