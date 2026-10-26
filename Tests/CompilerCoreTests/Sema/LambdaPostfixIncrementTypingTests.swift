#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct LambdaPostfixIncrementTypingTests {
    @Test func testIndexedIncrementAndDecrementRemainTheLambdaResult() throws {
        let source = """
        class Box {
            operator fun get(index: Int): Int = index
            operator fun set(index: Int, value: Int) {}
        }
        class Grid {
            operator fun get(x: Int, y: Int, z: Int): Int = x
            operator fun set(x: Int, y: Int, z: Int, value: Int) {}
        }
        operator fun Int.inc(): Int = this
        operator fun Int.dec(): Int = this
        fun doTest(test: () -> Int) = test()
        fun test(box: Box, grid: Grid) {
            doTest { ++box[0] }
            doTest { box[0]-- }
            doTest { ++grid[0, 1, 2] }
            doTest { grid[0, 1, 2]-- }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testPrimitiveArrayIncrementAndDecrementRemainTheLambdaResult() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        val arr = intArrayOf(3)
        fun doTest(test: () -> Int) = test()
        fun test() {
            doTest { ++arr[0] }
            doTest { arr[0]-- }
        }
        """, allowDefaultStdlibLibrary: true)

        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testPostfixIncrementRemainsTheLambdaResult() throws {
        let ctx = makeContextFromSources([
            """
            fun functionValue(): () -> Int {
                var counter = 1
                return { counter++ }
            }

            fun decrementValue(): () -> Int {
                var counter = 1
                return { counter-- }
            }

            fun arrayInitializer() {
                var counter = 1
                val values = Array<Int>(2) { counter++ }
            }

            fun unitValue(): () -> Unit {
                var counter = 1
                return { counter++ }
            }

            fun explicitTrailingValue(): () -> Int {
                var counter = 1
                return { counter++; counter }
            }
            """,
        ])

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics.map(\.code))")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let lambdaIDs = allExprIDs(in: ast, path: ctx.options.inputs[0], ctx: ctx) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        }
        var lambdaReturnTypes: [TypeID] = []
        for lambdaID in lambdaIDs {
            let type = try #require(sema.bindings.exprType(for: lambdaID))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("Expected a function type for lambda \(lambdaID)")
                continue
            }
            lambdaReturnTypes.append(function.returnType)
        }

        #expect(lambdaReturnTypes.count == 5)
        #expect(lambdaReturnTypes.filter { $0 == sema.types.intType }.count == 4)
        #expect(lambdaReturnTypes.filter { $0 == sema.types.unitType }.count == 1)
    }
}
#endif
