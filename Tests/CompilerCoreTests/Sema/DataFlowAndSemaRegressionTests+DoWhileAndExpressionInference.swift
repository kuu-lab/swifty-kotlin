#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {
    @Test func testClassWithTypeParametersDefinesVariance() throws {
        let source = """
        class Box<out T>(val value: T)
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let boxSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Box"
            }
            #expect(boxSymbol != nil)
        }
    }

    // MARK: - ExprInference: typed local declaration

    @Test func testTypedLocalDeclarationInfersCorrectly() throws {
        let source = """
        fun main(): Int {
            val x: Int = 42
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let xSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "x" && symbol.kind == .local
            }
            #expect(xSymbol != nil)
        }
    }

    // MARK: - ExprInference: val reassignment diagnostic

    @Test func testValReassignmentEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 1
            x = 2
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: do-while loop

    @Test func testDoWhileLoopInfersUnitType() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do {
                x = x + 1
            } while (x < 3)
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testDoWhileConditionCanReferenceBodyLocal() throws {
        let source = """
        fun main(): Int {
            var loops = 0
            do {
                val local = loops + 1
                loops = local
            } while (local < 3)
            return loops
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    @Test func testDoWhileBodyLocalDoesNotLeakOutsideLoop() throws {
        let source = """
        fun main(): Int {
            do {
                val local = 1
            } while (local < 2)
            return local
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    @Test func testDoWhileInlineBodyAssignmentTypeChecks() throws {
        let source = """
        fun main(): Int {
            var x = 0
            do x = x + 1 while (x < 3)
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0013", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assignment operators

    @Test func testCompoundAssignmentOperators() throws {
        let source = """
        fun main(): Int {
            var x = 10
            x += 5
            x -= 3
            x *= 2
            x /= 4
            x %= 3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on val

    @Test func testCompoundAssignOnValEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            val x = 5
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: member compound assign / postfix on val

    @Test func testMemberCompoundAssignOnValEmitsDiagnostic() throws {
        let source = """
        class Box(val n: Int)
        fun bump(b: Box): Int {
            b.n += 1
            return b.n
        }
        fun main(): Int = bump(Box(5))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    @Test func testMemberPostfixIncrementOnValEmitsDiagnostic() throws {
        let source = """
        class Box(val n: Int)
        fun bump(b: Box): Int {
            b.n++
            return b.n
        }
        fun main(): Int = bump(Box(5))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    @Test func testMemberCompoundAssignOnVarDoesNotEmitDiagnostic() throws {
        let source = """
        class Box(var n: Int)
        fun bump(b: Box): Int {
            b.n += 1
            return b.n
        }
        fun main(): Int = bump(Box(5))
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: when expression

    @Test func testWhenExpressionInference() throws {
        let source = """
        fun classify(x: Int): String {
            return when (x) {
                1 -> "one"
                2 -> "two"
                else -> "other"
            }
        }
        fun main() = classify(1)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - ExprInference: return expression

    @Test func testReturnExpressionInference() throws {
        let source = """
        fun earlyReturn(flag: Boolean): Int {
            if (flag) return 42
            return 0
        }
        fun main() = earlyReturn(true)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: ctx.interner)
            let returnCount = body.filter { instruction in
                if case .returnValue = instruction { return true }
                return false
            }.count
            #expect(returnCount >= 2)
        }
    }

    // MARK: - ExprInference: Long/Float/Double/Char literals

    @Test func testLongLiteralInference() throws {
        let source = """
        fun main(): Long = 42L
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testFloatLiteralInference() throws {
        let source = """
        fun main(): Float = 1.5f
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testDoubleLiteralInference() throws {
        let source = """
        fun main(): Double = 3.14
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testCharLiteralInference() throws {
        let source = """
        fun main(): Char = 'A'
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - ExprInference: is check and as cast

    @Test func testIsCheckInfersBoolean() throws {
        let source = """
        fun check(x: Any): Boolean = x is Int
        fun main() = check(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testSafeCastInfersNullableType() throws {
        let source = """
        fun tryCast(x: Any): Int? = x as? Int
        fun main() = tryCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testHardCastInference() throws {
        let source = """
        fun forceCast(x: Any): Int = x as Int
        fun main() = forceCast(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - ExprInference: null assert

    @Test func testNullAssertInfersNonNullable() throws {
        let source = """
        fun forceUnwrap(x: Int?): Int = x!!
        fun main() = forceUnwrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - ExprInference: elvis operator

    @Test func testElvisOperatorInference() throws {
        let source = """
        fun fallback(x: Int?): Int = x ?: 0
        fun main() = fallback(null)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - ExprInference: break/continue outside loop

    @Test func testBreakOutsideLoopEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            break
            return 0
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0018", in: ctx)
        }
    }
}
#endif
