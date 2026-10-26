@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct StringMapIndexedNotNullMixedResultTests {
    @Test
    func preservesCharAndNullableIntBranchTypes() throws {
        // Keep the branch types explicit; the nested generic reproducer is
        // covered by the backend and kotlinc differential tests.
        let source = """
        fun main() {
            val digits = mapOf("six" to 6)
            val number: Int? = digits["six"]
            val inferred = "7s".mapIndexedNotNull { _, c ->
                if (c.isDigit()) c else number
            }
            val explicit: List<Any> = "7s".mapIndexedNotNull { _, c ->
                if (c.isDigit()) c else number
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let branches = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
                guard sema.bindings.exprType(for: id) != nil else { return false }
                if case .ifExpr = expr { return true }
                return false
            }
            #expect(branches.count == 2)
            for id in branches {
                guard case let .ifExpr(_, thenExpr, elseExpr?, _) = ast.arena.expr(id) else { continue }
                #expect(sema.bindings.exprType(for: thenExpr) == sema.types.charType)
                #expect(sema.bindings.exprType(for: elseExpr) == sema.types.makeNullable(sema.types.intType))
                #expect(sema.bindings.exprType(for: id) == sema.types.nullableAnyType)
            }
        }
    }
}
