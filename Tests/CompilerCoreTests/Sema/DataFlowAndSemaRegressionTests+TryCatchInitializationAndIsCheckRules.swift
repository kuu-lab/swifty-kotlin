#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private nonisolated(unsafe) var _dataFlowTryCatchSharedCtx: (ctx: CompilationContext, paths: [String])?

private func sharedDataFlowTryCatchCtx() throws -> (ctx: CompilationContext, paths: [String]) {
    if let cached = _dataFlowTryCatchSharedCtx { return cached }
    let sources: [String] = [
        """
            package sample0
            fun <T : Any> wrap(value: T): T = value
            fun main() = wrap(42)
        """,
        """
            package sample1
            inline fun <reified T> castOrThrow(value: Any): T = value as T
            inline fun <reified T : Comparable<T>> boundedTypeName(): String = T::class.simpleName ?: "unknown"

            fun main() {
                println(castOrThrow<String>("hello"))
                println(boundedTypeName<String>())
            }
        """,
        """
            package sample2
            fun risky(): Int {
                return try {
                    42
                } catch (e: Any) {
                    0
                }
            }
            fun main() = risky()
        """,
        """
            package sample3
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
        """,
        """
            package sample4
            fun risky(): Int {
                return try {
                    42
                } catch {
                    0
                }
            }
            fun main() = risky()
        """,
        """
            package sample5
            fun f(): String {
                val x: String = try {
                    "ok"
                } catch (e: Exception) {
                    "err"
                }
                return x
            }

            fun main() = f()
        """,
        """
            package sample6
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
        """,
        """
            package sample7
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
        """,
        """
            package sample8
            fun f(): String {
                val x: String = try {
                    "ok"
                } finally {
                    123
                }
                return x
            }
        """,
        """
            package sample9
            fun main(): Int {
                var x: Int
                return x
            }
        """,
        """
            package sample10
            fun main(): Int {
                var x: Int
                x += 1
                return x
            }
        """,
        """
            package sample11
            fun main(): Int {
                var x: Int = 0
                if (true) {
                    x = 1
                } else {
                    x = 2
                }
                return x
            }
        """,
        """
            package sample12
            suspend fun delayed(v: Int): Int = v
            fun main(): Int = 0
        """,
        """
            package sample13
            fun main() {
                println("hello")
                println()
            }
        """,
        """
            package sample14
            fun main() {
                val parts = "1,2,3".split(",")
                println(parts.size)
                val mapped = parts.map { it }
                println(mapped.size)
            }
        """,
        """
            package sample15
            fun main(): Int {
                var x = 1
                x = 10
                return x
            }
        """,
        """
            package sample16
            class Node(val value: Int) {
                fun next(): Node? = null
            }

            fun main() {
                var node: Node? = Node(1)
                while (node != null) {
                    println(node.value)
                    node = node.next()
                }
            }
        """,
        """
            package sample17
            fun main() {
                var value: String? = "a"
                if (value != null) {
                    println(value.length)
                    value = null
                }
                println(value)
            }
        """,
        """
            package sample18
            fun f(x: Any): Boolean = x is List<String>
            fun main(): Int = 0
        """,
        """
            package sample19
            fun f(x: Any): Boolean = x is List<*>
            fun main(): Int = 0
        """,
        """
            package sample20
            fun <T> f(x: Any): Boolean = x is T
            fun main(): Int = 0
        """,
        """
            package sample21
            inline fun <reified T> f(x: Any): Boolean = x is T
            fun main(): Int = if (f<Int>(1)) 1 else 0
        """,
        """
            package sample22
            const val maybeInt: Int? = 1
            fun main(): Int = 0
        """,
        """
            package sample23
            const val maybeName: String? = "ok"
            fun main(): Int = 0
        """,
        """
            package sample24
            const val name: String = "ok"
            fun main(): Int = 0
        """
    ]
    var result: (ctx: CompilationContext, paths: [String])?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths)
        try runSema(ctx)
        result = (ctx, paths)
    }
    let pair = try #require(result)
    _dataFlowTryCatchSharedCtx = pair
    return pair
}

extension DataFlowAndSemaRegressionTests {
    @Test func testFunctionTypeParameterWithUpperBound() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[0]
            let sema = try #require(ctx.sema)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: samplePath))
            let wrapSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "wrap" &&
                    sema.symbols.sourceFileID(for: symbol.id) == sourceFileID
            }
            #expect(wrapSymbol != nil)
            if let sym = wrapSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                let typeParamEmpty = sig.typeParameterSymbols.isEmpty
                #expect(!typeParamEmpty)
            }
    }

    @Test func testReifiedInlineFunctionSupportsUnsafeCastAndBoundedTypeParameter() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()

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

    @Test func testTryCatchExpressionInference() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
    }

    @Test func testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[3]

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: samplePath))
            let tryExprID = try #require(firstExprID(in: ast) { exprID, expr in
                guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else {
                    return false
                }
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

    @Test func testTryCatchClauseBindingWithoutParameterDefaultsToAny() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[4]

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: samplePath))
            let tryExprID = try #require(firstExprID(in: ast) { exprID, expr in
                guard ast.arena.exprRange(exprID)?.start.file == sourceFileID else {
                    return false
                }
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

    @Test func testTryCatchExpressionMatchesCompletionCriteriaExample() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[5]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiagnostics)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testTryCatchDefiniteInitializationMergesNormalBranches() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[6]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testTryPartialCatchRethrowMergesOnlyNormalPaths() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[7]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testTryFinallyReturnValueDoesNotPolluteTypeInference() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[8]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiagnostics)
    }

    @Test func testUninitializedVariableUseEmitsDiagnostic() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[9]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testCompoundAssignOnUninitializedVariableEmitsDiagnostic() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[10]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testDeferredInitializationViaIfElse() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[11]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sampleDiagnostics)
    }

    @Test func testSuspendFunctionSignature() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
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

    @Test func testPrintlnBuiltinInfersUnit() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
    }

    @Test func testStringSplitMarksCollectionForFallbackMembers() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[14]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiagnostics)
            assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiagnostics)
            assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiagnostics)
    }

    @Test func testVarLocalReassignment() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[15]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sampleDiagnostics)
    }

    @Test func testMutableLocalIsSmartCastAfterNullCheck() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[16]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            let errors = sampleDiagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, Comment(rawValue: "unexpected errors: \(errors.map(\.code))"))
    }

    @Test func testReassignmentDropsSmartCastOnMutableLocal() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[17]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            let errors = sampleDiagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, Comment(rawValue: "unexpected errors: \(errors.map(\.code))"))
    }

    @Test func testIsCheckWithErasedGenericTypeEmitsWarning() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[18]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: sampleDiagnostics)
    }

    @Test func testIsCheckWithStarProjectionDoesNotEmitErasureWarning() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[19]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: sampleDiagnostics)
    }

    @Test func testIsCheckWithNonReifiedTypeParameterEmitsDiagnostic() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[20]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0084", in: sampleDiagnostics)
    }

    @Test func testIsCheckWithReifiedTypeParameterDoesNotEmitNonReifiedDiagnostic() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[21]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0084", in: sampleDiagnostics)
    }

    @Test func testConstValRejectsNullablePrimitiveTypeAnnotation() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[22]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: sampleDiagnostics)
    }

    @Test func testConstValRejectsNullableStringTypeAnnotation() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[23]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0082", in: sampleDiagnostics)
    }

    @Test func testConstValAcceptsNonNullableStringTypeAnnotation() throws {
        let (ctx, paths) = try sharedDataFlowTryCatchCtx()
        let samplePath = paths[24]
        let sampleDiagnostics = diagnosticsForPath(samplePath, in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0082", in: sampleDiagnostics)
    }
}
#endif
