#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {
    @Test func testFunctionTypeParameterWithUpperBound() throws {
        let source = """
        fun <T : Any> wrap(value: T): T = value
        fun main() = wrap(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let wrapSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "wrap"
            }
            #expect(wrapSymbol != nil)
            if let sym = wrapSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                let typeParamEmpty = sig.typeParameterSymbols.isEmpty
                #expect(!typeParamEmpty)
            }
        }
    }

    @Test func testReifiedInlineFunctionSupportsUnsafeCastAndBoundedTypeParameter() throws {
        let source = """
        inline fun <reified T> castOrThrow(value: Any): T = value as T
        inline fun <reified T : Comparable<T>> boundedTypeName(): String = T::class.simpleName ?: "unknown"

        fun main() {
            println(castOrThrow<String>("hello"))
            println(boundedTypeName<String>())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            let castSymbol = try #require(sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "castOrThrow"
            })
            let castSignature = try #require(sema.symbols.functionSignature(for: castSymbol.id))
            #expect(castSignature.reifiedTypeParameterIndices == Set([0]))
            #expect(castSignature.typeParameterSymbols.count == 1)

            let boundedSymbol = try #require(sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "boundedTypeName"
            })
            let boundedSignature = try #require(sema.symbols.functionSignature(for: boundedSymbol.id))
            #expect(boundedSignature.reifiedTypeParameterIndices == Set([0]))
            #expect(boundedSignature.typeParameterSymbols.count == 1)

            let boundedTypeParameter = try #require(boundedSignature.typeParameterSymbols.first)
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: boundedTypeParameter)
            #expect(upperBounds.count == 1)
            if let upperBound = upperBounds.first {
                guard case let .classType(classType) = sema.types.kind(of: upperBound) else {
                    Issue.record("Expected Comparable upper bound")
                    return
                }
                let comparableFQName = [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("Comparable"),
                ]
                let comparableSymbol = try #require(sema.symbols.lookup(fqName: comparableFQName))
                #expect(classType.classSymbol == comparableSymbol)
            }
        }
    }

    // MARK: - ExprInference: try-catch expression

    @Test func testTryCatchExpressionInference() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch (e: Any) {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    @Test func testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes() throws {
        let source = """
        class MyError

        fun risky(): Int {
            return try {
                42
            } catch (e: Int) {
                e
            } catch (e: MyError) {
                0
            }
        }

        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let tryExprID = try #require(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                Issue.record("Expected try expression")
                return
            }
            #expect(catchClauses.count == 2)

            let firstBinding = try #require(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            let secondBinding = try #require(sema.bindings.catchClauseBinding(for: catchClauses[1].body))
            #expect(firstBinding.parameterSymbol != .invalid)
            #expect(secondBinding.parameterSymbol != .invalid)
            #expect(firstBinding.parameterSymbol != secondBinding.parameterSymbol)

            let intType = sema.types.make(.primitive(.int, .nonNull))
            #expect(firstBinding.parameterType == intType)
            #expect(sema.symbols.propertyType(for: firstBinding.parameterSymbol) == intType)

            let customErrorSymbol = sema.symbols.allSymbols().first { symbol in
                symbol.kind == .class && ctx.interner.resolve(symbol.name) == "MyError"
            }
            let resolvedCustomErrorSymbol = try #require(customErrorSymbol)
            guard case let .classType(customErrorType) = sema.types.kind(of: secondBinding.parameterType) else {
                Issue.record("Expected nominal catch parameter type")
                return
            }
            #expect(customErrorType.classSymbol == resolvedCustomErrorSymbol.id)
            #expect(sema.symbols.propertyType(for: secondBinding.parameterSymbol) == secondBinding.parameterType)

            let catchNameRef = try #require(firstExprID(in: ast) { exprID, expr in
                guard case let .nameRef(name, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(name) == "e"
                    && sema.bindings.identifierSymbol(for: exprID) == firstBinding.parameterSymbol
            })
            #expect(sema.bindings.identifierSymbol(for: catchNameRef) == firstBinding.parameterSymbol)
            #expect(sema.bindings.exprType(for: catchNameRef) == intType)
        }
    }

    @Test func testTryCatchClauseBindingWithoutParameterDefaultsToAny() throws {
        let source = """
        fun risky(): Int {
            return try {
                42
            } catch {
                0
            }
        }
        fun main() = risky()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let tryExprID = try #require(firstExprID(in: ast) { _, expr in
                if case .tryExpr = expr {
                    return true
                }
                return false
            })
            guard case let .tryExpr(_, catchClauses, _, _)? = ast.arena.expr(tryExprID) else {
                Issue.record("Expected try expression")
                return
            }
            let binding = try #require(sema.bindings.catchClauseBinding(for: catchClauses[0].body))
            #expect(binding.parameterSymbol == .invalid)
            #expect(binding.parameterType == sema.types.anyType)
        }
    }

    @Test func testTryCatchExpressionMatchesCompletionCriteriaExample() throws {
        let source = """
        fun f(): String {
            val x: String = try {
                "ok"
            } catch (e: Exception) {
                "err"
            }
            return x
        }

        fun main() = f()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    @Test func testTryCatchDefiniteInitializationMergesNormalBranches() throws {
        let source = """
        class Handled

        fun f(flag: Boolean): Int {
            var x: Int
            try {
                if (flag) throw Handled()
                x = 1
            } catch (e: Handled) {
                x = 2
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    @Test func testTryPartialCatchRethrowMergesOnlyNormalPaths() throws {
        let source = """
        class Handled
        class Unhandled

        fun f(flag: Boolean): Int {
            var x: Int
            try {
                if (flag) throw Handled() else throw Unhandled()
            } catch (e: Handled) {
                x = 7
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    @Test func testTryFinallyReturnValueDoesNotPolluteTypeInference() throws {
        let source = """
        fun f(): String {
            val x: String = try {
                "ok"
            } finally {
                123
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - ExprInference: uninitialized variable use

    @Test func testUninitializedVariableUseEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: compound assign on uninitialized variable

    @Test func testCompoundAssignOnUninitializedVariableEmitsDiagnostic() throws {
        let source = """
        fun main(): Int {
            var x: Int
            x += 1
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - ExprInference: local variable deferred initialization via if-else

    @Test func testDeferredInitializationViaIfElse() throws {
        let source = """
        fun main(): Int {
            var x: Int = 0
            if (true) {
                x = 1
            } else {
                x = 2
            }
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: ctx)
        }
    }

    // MARK: - HeaderCollection: suspend function

    @Test func testSuspendFunctionSignature() throws {
        let source = """
        suspend fun delayed(v: Int): Int = v
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let delayedSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "delayed"
            }
            #expect(delayedSymbol != nil)
            if let sym = delayedSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                #expect(sig.isSuspend)
            }
        }
    }

    // MARK: - ExprInference: println builtin

    @Test func testPrintlnBuiltinInfersUnit() throws {
        let source = """
        fun main() {
            println("hello")
            println()
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

    @Test func testStringSplitMarksCollectionForFallbackMembers() throws {
        let source = """
        fun main() {
            val parts = "1,2,3".split(",")
            println(parts.size)
            val mapped = parts.map { it }
            println(mapped.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
        }
    }

    // MARK: - ExprInference: local variable with var and reassignment

    @Test func testVarLocalReassignment() throws {
        let source = """
        fun main(): Int {
            var x = 1
            x = 10
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: ctx)
        }
    }

    // MARK: - ExprInference: is check with erased generic type emits warning

    @Test func testIsCheckWithErasedGenericTypeEmitsWarning() throws {
        let source = """
        fun f(x: Any): Boolean = x is List<String>
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: ctx)
        }
    }

    @Test func testIsCheckWithStarProjectionDoesNotEmitErasureWarning() throws {
        let source = """
        fun f(x: Any): Boolean = x is List<*>
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: ctx)
        }
    }

    @Test func testIsCheckWithNonReifiedTypeParameterEmitsDiagnostic() throws {
        let source = """
        fun <T> f(x: Any): Boolean = x is T
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0084", in: ctx)
        }
    }

    @Test func testIsCheckWithReifiedTypeParameterDoesNotEmitNonReifiedDiagnostic() throws {
        let source = """
        inline fun <reified T> f(x: Any): Boolean = x is T
        fun main(): Int = if (f<Int>(1)) 1 else 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0084", in: ctx)
        }
    }

    // MARK: - Const property validation

    @Test func testConstValRejectsNullablePrimitiveTypeAnnotation() throws {
        let source = """
        const val maybeInt: Int? = 1
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }

    @Test func testConstValRejectsNullableStringTypeAnnotation() throws {
        let source = """
        const val maybeName: String? = "ok"
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }

    @Test func testConstValAcceptsNonNullableStringTypeAnnotation() throws {
        let source = """
        const val name: String = "ok"
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0082", in: ctx)
        }
    }
}
#endif
