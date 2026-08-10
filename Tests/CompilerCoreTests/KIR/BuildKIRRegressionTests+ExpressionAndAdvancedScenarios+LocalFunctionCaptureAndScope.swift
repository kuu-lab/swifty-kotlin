#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {

    @Test func testLocalFunctionCaptureAndScopeKIR() throws {
        let sources: [String] = [
            // 0: nested local function scope resolution
            """
            fun outerScope(): Int {
                fun middleScope(): Int {
                    fun innerScope(): Int = 7
                    return innerScope()
                }
                return middleScope()
            }
            fun mainScope() = outerScope()
            """,

            // 1: local function with block body
            """
            fun mainBlock(): Int {
                fun computeBlock(x: Int): Int {
                    val doubled = x * 2
                    return doubled + 1
                }
                return computeBlock(10)
            }
            """,

            // 2: local function called multiple times
            """
            fun mainMultiple(): Int {
                fun squareMultiple(n: Int): Int = n * n
                val a = squareMultiple(3)
                val b = squareMultiple(4)
                return a + b
            }
            """,

            // 3: local function captures outer val
            """
            fun mainCaptureVal(): Int {
                val outerCapture = 10
                fun addOuter(x: Int): Int = x + outerCapture
                return addOuter(5)
            }
            """,

            // 4: nested local function capture from parent scope
            """
            fun outerCaptureParent(): Int {
                fun middleCaptureParent(): Int {
                    val xParent = 5
                    fun innerCaptureParent(): Int = xParent + 1
                    return innerCaptureParent()
                }
                return middleCaptureParent()
            }
            fun mainCaptureParent() = outerCaptureParent()
            """,

            // 5: nested local function infers expression-body return type
            """
            fun mainInfer(): Int {
                fun outerInfer(x: Int): Int {
                    fun innerInfer(y: Int) = x + y
                    return innerInfer(10)
                }
                return outerInfer(5)
            }
            """,

            // 6: local function captures mutable outer var with postfix increment
            """
            fun mainMutable(): Int {
                var counterMutable = 0
                fun incrementMutable() {
                    counterMutable++
                }
                incrementMutable()
                incrementMutable()
                return counterMutable
            }
            """,

            // 7: local function captures mutable outer var with postfix increment and semicolon
            """
            fun mainMutableSemi(): Int {
                var counterMutableSemi = 0
                fun incrementMutableSemi() {
                    counterMutableSemi++;
                }
                incrementMutableSemi();
                incrementMutableSemi();
                return counterMutableSemi
            }
            """,

            // 8: local function captures multiple outer vals
            """
            fun computeMulti(): Int {
                val aMulti = 10
                val bMulti = 20
                fun sumMulti(): Int = aMulti + bMulti
                return sumMulti()
            }
            fun mainMulti() = computeMulti()
            """,

            // 9: local function scope does not leak between top-level functions (error)
            """
            fun firstLeak(): Int {
                fun helperLeak(): Int = 1
                return helperLeak()
            }
            fun secondLeak(): Int {
                return helperLeak()
            }
            """,

            // 10: nested local function call forwards capture arguments
            """
            fun mainForward(): Int {
                val xForward = 10
                fun gForward(): Int = xForward
                fun hForward(): Int = gForward()
                return hForward()
            }
            """,

            // 11: nested local function forwards non-literal val capture
            """
            fun mainNonLiteral(): Int {
                val xNonLiteral = 1 + 2
                fun gNonLiteral(): Int = xNonLiteral
                fun hNonLiteral(): Int = gNonLiteral()
                return hNonLiteral()
            }
            """,

            // 12: nested local function forwards value parameter capture
            """
            fun mainParamCapture(pParamCapture: Int): Int {
                fun gParamCapture(): Int = pParamCapture
                fun hParamCapture(): Int = gParamCapture()
                return hParamCapture()
            }
            """,

            // 13: recursive local function with capture
            """
            fun mainRecursive(): Int {
                val limitRecursive = 10
                fun countdownRecursive(n: Int): Int {
                    if (n <= 0) return limitRecursive
                    return countdownRecursive(n - 1)
                }
                countdownRecursive(5)
                return 0
            }
            """,

            // 14: suspend local function generates suspend KIR function
            """
            suspend fun delayedValueSuspend(v: Int): Int = v

            suspend fun outerSuspendHost(value: Int): Int {
                suspend fun localSuspendBridge(value: Int): Int = delayedValueSuspend(value)
                return localSuspendBridge(value)
            }

            fun mainSuspend(): Any? = runBlocking(outerSuspendHost)
            """,

            // 15: local function shadows top-level extension of same name
            """
            fun String.shadowNameTop(): String = "extension"
            fun mainShadow(): String {
                fun shadowNameLocal(): String = "local"
                return shadowNameLocal()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let allFunctions = findAllKIRFunctions(in: module)
            let functionNames = Set(allFunctions.map { ctx.interner.resolve($0.name) })

            // Scenario 0
            do {
                let diags = diagnosticsForPath(paths[0], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("outerScope"))
                #expect(functionNames.contains("mainScope"))
            }

            // Scenario 1
            do {
                let diags = diagnosticsForPath(paths[1], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainBlock"))
            }

            // Scenario 2
            do {
                let diags = diagnosticsForPath(paths[2], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainMultiple"))
            }

            // Scenario 3
            do {
                let diags = diagnosticsForPath(paths[3], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainCaptureVal"))
            }

            // Scenario 4
            do {
                let diags = diagnosticsForPath(paths[4], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("outerCaptureParent"))
                #expect(functionNames.contains("mainCaptureParent"))
            }

            // Scenario 5
            do {
                let diags = diagnosticsForPath(paths[5], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainInfer"))
            }

            // Scenario 6
            do {
                let diags = diagnosticsForPath(paths[6], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainMutable"))
            }

            // Scenario 7
            do {
                let diags = diagnosticsForPath(paths[7], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainMutableSemi"))
            }

            // Scenario 8
            do {
                let diags = diagnosticsForPath(paths[8], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("computeMulti"))
                #expect(functionNames.contains("mainMulti"))
            }

            // Scenario 9: scope leakage error
            do {
                let diags = diagnosticsForPath(paths[9], in: ctx)
                #expect(
                    diags.contains(where: { $0.severity == .error }),
                    "Local function should not be visible outside its defining top-level function: \(diags.map { $0.message })"
                )
            }

            // Scenario 10
            do {
                let diags = diagnosticsForPath(paths[10], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainForward"))
            }

            // Scenario 11
            do {
                let diags = diagnosticsForPath(paths[11], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainNonLiteral"))
            }

            // Scenario 12
            do {
                let diags = diagnosticsForPath(paths[12], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainParamCapture"))
            }

            // Scenario 13
            do {
                let diags = diagnosticsForPath(paths[13], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainRecursive"))
            }

            // Scenario 14: suspend local function
            do {
                let diags = diagnosticsForPath(paths[14], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainSuspend"))
                #expect(functionNames.contains("outerSuspendHost"))

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

            // Scenario 15
            do {
                let diags = diagnosticsForPath(paths[15], in: ctx)
                #expect(!diags.contains(where: { $0.severity == .error }))
                #expect(functionNames.contains("mainShadow"))
            }

            // Overall function count sanity check (sum of per-scenario minimums).
            #expect(module.functionCount >= 43, "Expected at least 43 KIR functions for all scenarios, got \(module.functionCount)")
        }
    }
}
#endif
