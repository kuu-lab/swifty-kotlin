#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {

    private static nonisolated(unsafe) var _sharedLocalFunctionCtx: CompilationContext?

    private func sharedLocalFunctionCtx() throws -> CompilationContext {
        if let cached = Self._sharedLocalFunctionCtx { return cached }
        let sources: [String] = [
            """
            package sample0
            fun outer(): Int {
                fun middle(): Int {
                    fun inner(): Int = 7
                    return inner()
                }
                return middle()
            }
            fun main0() = outer()
            """,
            """
            package sample1
            fun main1(): Int {
                fun compute(x: Int): Int {
                    val doubled = x * 2
                    return doubled + 1
                }
                return compute(10)
            }
            """,
            """
            package sample2
            fun main2(): Int {
                fun square(n: Int): Int = n * n
                val a = square(3)
                val b = square(4)
                return a + b
            }
            """,
            """
            package sample3
            fun main3(): Int {
                val outer = 10
                fun addOuter(x: Int): Int = x + outer
                return addOuter(5)
            }
            """,
            """
            package sample4
            fun outer(): Int {
                fun middle(): Int {
                    val x = 5
                    fun inner(): Int = x + 1
                    return inner()
                }
                return middle()
            }
            fun main4() = outer()
            """,
            """
            package sample5
            fun main5(): Int {
                fun outer(x: Int): Int {
                    fun inner(y: Int) = x + y
                    return inner(10)
                }
                return outer(5)
            }
            """,
            """
            package sample6
            fun main6(): Int {
                var counter = 0
                fun increment() {
                    counter++
                }
                increment()
                increment()
                return counter
            }
            """,
            """
            package sample7
            fun main7(): Int {
                var counter = 0
                fun increment() {
                    counter++;
                }
                increment();
                increment();
                return counter
            }
            """,
            """
            package sample8
            fun compute(): Int {
                val a = 10
                val b = 20
                fun sum(): Int = a + b
                return sum()
            }
            fun main8() = compute()
            """,
            """
            package sample10
            fun main10(): Int {
                val x = 10
                fun g(): Int = x
                fun h(): Int = g()
                return h()
            }
            """,
            """
            package sample11
            fun main11(): Int {
                val x = 1 + 2
                fun g(): Int = x
                fun h(): Int = g()
                return h()
            }
            """,
            """
            package sample12
            fun main12(p: Int): Int {
                fun g(): Int = p
                fun h(): Int = g()
                return h()
            }
            """,
            """
            package sample13
            fun main13() {
                val limit = 10
                fun countdown(n: Int): Int {
                    if (n <= 0) return limit
                    return countdown(n - 1)
                }
                countdown(5)
            }
            """,
            """
            package sample14
            suspend fun delayedValue(v: Int): Int = v

            suspend fun outerSuspendHost(value: Int): Int {
                suspend fun localSuspendBridge(value: Int): Int = delayedValue(value)
                return localSuspendBridge(value)
            }

            fun main14(): Any? = runBlocking(outerSuspendHost)
            """,
            """
            package sample15
            fun String.shadowName(): String = "extension"
            fun main15(): String {
                fun shadowName(): String = "local"
                return shadowName()
            }
            """
        ]
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedLocalFunctionCtx = ctx
        return ctx
    }

    private static nonisolated(unsafe) var _sharedLocalFunctionErrorCtx: CompilationContext?

    private func sharedLocalFunctionErrorCtx() throws -> CompilationContext {
        if let cached = Self._sharedLocalFunctionErrorCtx { return cached }
        let sources: [String] = [
            """
            package sample9
            fun first(): Int {
                fun helper(): Int = 1
                return helper()
            }
            fun second(): Int {
                return helper()
            }
            """
        ]
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedLocalFunctionErrorCtx = ctx
        return ctx
    }

    @Test
    func testNestedLocalFunctionScopeResolution() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Nested local functions should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // outer, middle, inner, main => at least 4 functions
        #expect(module.functionCount >= 4)
    }

    @Test
    func testLocalFunctionWithBlockBodyKIRGeneration() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Local function with block body: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 2)
    }

    @Test
    func testLocalFunctionCalledMultipleTimes() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Multiple calls to local function: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test
    func testLocalFunctionCapturesOuterVal() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Local function capturing outer val should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 2)
    }

    @Test
    func testNestedLocalFunctionCaptureFromParentScope() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Nested local function capture should be handled: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // outer, middle, inner, main => at least 4 functions with capture analysis performed correctly
        #expect(module.functionCount >= 4)
    }

    @Test
    func testNestedLocalFunctionInfersExpressionBodyReturnType() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Nested local function expression-body return type should be inferred: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 3)
    }

    @Test
    func testLocalFunctionCapturesMutableOuterVarWithPostfixIncrement() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Local function mutable capture with postfix increment should compile: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 2)
    }

    @Test
    func testLocalFunctionCapturesMutableOuterVarWithPostfixIncrementAndSemicolon() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Local function mutable capture with postfix increment and semicolon should compile: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 2)
    }

    @Test
    func testLocalFunctionCapturesMultipleOuterVals() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Local function capturing multiple outer vals should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // compute, sum, main => at least 3 functions
        #expect(module.functionCount >= 3)
    }

    @Test
    func testNestedLocalFunctionCallForwardsCaptureArguments() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Nested local function call with capture forwarding should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // main, g, h => at least 3 functions
        #expect(module.functionCount >= 3, "Expected at least 3 functions (main + g + h)")
    }

    @Test
    func testNestedLocalFunctionForwardsNonLiteralValCapture() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Nested local function forwarding non-literal val capture should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // main, g, h => at least 3 functions
        #expect(module.functionCount >= 3, "Expected at least 3 functions (main + g + h)")
    }

    @Test
    func testNestedLocalFunctionForwardsValueParameterCapture() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Nested local function forwarding value parameter capture should compile: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // main, g, h => at least 3 functions
        #expect(module.functionCount >= 3, "Expected at least 3 functions (main + g + h)")
    }

    @Test
    func testRecursiveLocalFunctionWithCaptureResolvesCorrectly() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(!(ctx.diagnostics.hasError), "Recursive local function with capture should compile without errors: \(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        // Should have at least main + countdown
        #expect(module.functionCount >= 2, "Expected at least 2 functions (main + countdown)")
    }

    @Test
    func testSuspendLocalFunctionGeneratesSuspendKIRFunction() throws {
        let ctx = try sharedLocalFunctionCtx()

        #expect(
            !(ctx.diagnostics.hasError),
            "Suspend local function should compile into KIR without errors: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let module = try #require(ctx.kir)
        let allFunctions = findAllKIRFunctions(in: module)

        let localSuspendFunction = try #require(allFunctions.first(where: { function in
            ctx.interner.resolve(function.name) == "localSuspendBridge"
        }))
        #expect(localSuspendFunction.isSuspend, "Expected local suspend function KIR node to preserve isSuspend flag.")

        let outerSuspendFunction = try #require(allFunctions.first(where: { function in
            ctx.interner.resolve(function.name) == "outerSuspendHost"
        }))
        let outerCallees = extractCallees(from: outerSuspendFunction.body, interner: ctx.interner)
        #expect(outerCallees.contains("localSuspendBridge"), "Expected outer suspend function to call the local suspend function before lowering.")
    }

    @Test
    func testLocalFunctionShadowsTopLevelExtensionOfSameName() throws {
        let ctx = try sharedLocalFunctionCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Local function should shadow top-level extension of the same name: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(module.functionCount >= 2)
    }

    @Test
    func testLocalFunctionScopeDoesNotLeakBetweenTopLevelFunctions() throws {
        let ctx = try sharedLocalFunctionErrorCtx()
        #expect(
            ctx.diagnostics.hasError,
            "Local function should not be visible outside its defining top-level function: \(ctx.diagnostics.diagnostics.map(\.message))"
        )
    }

    func firstExprID(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else {
                continue
            }
            if predicate(exprID, expr) {
                return exprID
            }
        }
        return nil
    }
}
#endif
