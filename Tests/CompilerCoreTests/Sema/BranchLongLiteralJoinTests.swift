#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BranchLongLiteralJoinTests {
    @Test(arguments: [false, true])
    func literalsJoinLongBranches(useCache: Bool) throws {
        let source = """
            fun f(endIndex: Long): Long = endIndex
            fun g(x: Long): Long {
                val e = when (x) { -1L -> 5L; 0L -> 101; else -> x - 1 }
                return f(endIndex = e)
            }
            fun h(x: Long): Long {
                val e = if (x > 0) x else 102
                return f(e)
            }
            fun reversed(x: Long): Long {
                val e = if (x > 0) -103 else x
                return f(e)
            }
            fun blocks(x: Long): Long {
                val e = when { x > 0 -> { val unused = 1; +104 }; else -> x }
                return f(e)
            }
            fun nested(x: Long, flag: Boolean): Long {
                val e = if (flag) { if (flag) 105 else 106 } else x
                return f(e)
            }
            fun nullable(x: Long?, flag: Boolean): Long? {
                val e = if (flag) x else 107
                return e
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], frontendFlags: useCache ? ["sema-cache"] : [],
                includeStdlib: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map { $0.message })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for value in 101 ... 107 {
                let literal = try #require(firstExprID(in: ast) { _, expr in
                    if case let .intLiteral(actual, _) = expr { return actual == Int64(value) }
                    return false
                })
                #expect(sema.bindings.exprType(for: literal) == sema.types.longType)
            }
        }
    }

    @Test(arguments: [
        "val e = if (flag) x else i",
        "val e = when (x) { 0L -> i; else -> x }",
        "val e = when { flag -> i; else -> x }",
        "val e = if (flag) x else i + 1",
    ])
    func intExpressionsAreNotWidened(declaration: String) throws {
        let source = """
            fun f(value: Long): Long = value
            fun bad(x: Long, i: Int, flag: Boolean): Long {
                \(declaration)
                return f(e)
            }
            """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        }
    }
}
#endif
