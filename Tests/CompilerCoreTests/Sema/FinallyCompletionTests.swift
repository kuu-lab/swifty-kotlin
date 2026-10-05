#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FinallyCompletionTests {
    @Test func testTerminatingFinallyCompletesBlockBodiesWithoutTrailingReturn() throws {
        let ctx = makeContextFromSources([
            """
            fun escape(): Int {
                try { println("try") } finally { return 36 }
            }
            fun caught(): Int {
                try { println("try") }
                catch (e: Exception) { println("catch") }
                finally { return 37 }
            }
            fun nested(): Int {
                try { println("outer") }
                finally { try { println("inner") } finally { return 38 } }
            }
            fun branches(flag: Boolean): Int {
                if (flag) {
                    try { println("left") } finally { return 39 }
                } else {
                    try { println("right") } finally { return 40 }
                }
            }
            fun exhaustive(flag: Boolean): Int {
                when (flag) {
                    true -> try { println("true") } finally { return 41 }
                    false -> try { println("false") } finally { return 42 }
                }
            }
            fun subjectless(flag: Boolean): Int {
                when {
                    flag -> try { println("yes") } finally { return 43 }
                    else -> try { println("no") } finally { return 44 }
                }
            }
            fun conditional(flag: Boolean): Int {
                try { println("try") }
                finally { if (flag) return 45 else return 46 }
            }
            fun throwing(): Int {
                try { println("try") } finally { throw IllegalStateException("cleanup") }
            }
            fun fail(): Nothing = throw IllegalStateException("cleanup")
            fun nothingCall(): Int {
                try { println("try") } finally { fail() }
            }
            fun initializer(): Int {
                val ignored = try { 1 } finally { return 47 }
            }
            fun argument(): Int {
                println(try { 1 } finally { return 48 })
            }
            fun nestedCatch(): Int {
                try {
                    try { println("inner") } finally { return 49 }
                } catch (e: Exception) { return 50 }
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testFinallyDoesNotChangeTryExpressionStaticTypes() throws {
        let ctx = makeContextFromSources([
            """
            fun escape(): Int {
                try { println("try") } finally { return 36 }
            }
            fun value(): String {
                val ignored: Int = try { 1 } catch (e: Exception) { 2 } finally { return "escape" }
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let tryIDs = allExprIDs(in: ast, path: ctx.options.inputs[0], ctx: ctx) { _, expr in
            if case .tryExpr = expr { return true }
            return false
        }
        let tryTypes = try tryIDs.map { try #require(sema.bindings.exprType(for: $0)) }
        #expect(tryTypes == [sema.types.unitType, sema.types.intType])
    }

    @Test func testFallthroughAndInvalidReturnRemainRejected() throws {
        let sources = [
            "fun f(flag: Boolean): Int { try { println(1) } finally { if (flag) return 36 } }",
            "fun f(): Int { try { println(1) } finally { 36 } }",
            "fun f(): Int { try { println(1) } finally { return \"wrong\" } }",
            "fun f(flag: Boolean): Int { if (flag) try { println(1) } finally { return 36 } }",
            "fun f(flag: Boolean): Int { when { flag -> try { println(1) } finally { return 36 } } }",
            "fun f(): Int { try { println(1) } finally { val deferred = label@ { return@label 36 } } }",
            "fun f(): Int { try { try { println(1) } finally { throw IllegalStateException(\"caught\") } } catch (e: Exception) { println(2) } }",
            "fun f(flag: Boolean): Int { flag && (try { true } finally { return 36 }) }",
            "fun f(value: Int?): Int { value ?: (try { 1 } finally { return 36 }) }",
            "fun f(value: String?): Int { value?.contains(try { \"x\" } finally { return 36 }) }",
            "fun f(): String { val x: String = try { 1 } finally { return \"escape\" } }",
        ]
        let ctx = makeContextFromSources(sources.enumerated().map { index, source in
            "package sample\(index)\n\(source)"
        })
        try runSema(ctx)
        for index in sources.indices {
            let diagnostics = diagnosticsForPath(ctx.options.inputs[index], in: ctx)
            assertHasDiagnostic("KSWIFTK-TYPE-0001", in: diagnostics)
        }
    }

    @Test func testStatementsAfterTerminatingFinallyAreUnreachableButChecked() throws {
        let ctx = makeContextFromSources([
            """
            fun escape(): Int {
                try { println("try") } finally { return 36 }
                return "wrong"
            }
            """
        ])
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0096", in: ctx)
        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }
}
#endif
