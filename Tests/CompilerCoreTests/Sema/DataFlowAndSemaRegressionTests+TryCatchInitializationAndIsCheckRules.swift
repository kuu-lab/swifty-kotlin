#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {

    // MARK: - ExprInference: try-catch expression

    // MARK: - ExprInference: uninitialized variable use

    // MARK: - ExprInference: compound assign on uninitialized variable

    // MARK: - ExprInference: local variable deferred initialization via if-else

    // MARK: - HeaderCollection: suspend function

    // MARK: - ExprInference: println builtin

    // MARK: - ExprInference: local variable with var and reassignment

    // MARK: - ExprInference: is check with erased generic type emits warning

    // MARK: - Const property validation

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaCleanTryCatchInitializationAndIsCheckRules() throws {

        let sources: [String] = [
            // testFunctionTypeParameterWithUpperBound
            """
            package sample0

                    fun <T : Any> wrap(value: T): T = value
                    fun main() = wrap(42)

            """,
            // testReifiedInlineFunctionSupportsUnsafeCastAndBoundedTypeParameter
            """
            package sample1

                    inline fun <reified T> castOrThrow(value: Any): T = value as T
                    inline fun <reified T : Comparable<T>> boundedTypeName(): String = T::class.simpleName ?: "unknown"

                    fun main() {
                        println(castOrThrow<String>("hello"))
                        println(boundedTypeName<String>())
                    }

            """,
            // testTryCatchExpressionInference
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
            // testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes
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
            // testTryCatchClauseBindingWithoutParameterDefaultsToAny
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
            // testTryCatchExpressionMatchesCompletionCriteriaExample
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
            // testTryCatchDefiniteInitializationMergesNormalBranches
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
            // testTryPartialCatchRethrowMergesOnlyNormalPaths
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
            // testTryFinallyReturnValueDoesNotPolluteTypeInference
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
            // testSuspendFunctionSignature
            """
            package sample9

                    suspend fun delayed(v: Int): Int = v
                    fun main(): Int = 0

            """,
            // testStringSplitMarksCollectionForFallbackMembers
            """
            package sample10

                    fun main() {
                        val parts = "1,2,3".split(",")
                        println(parts.size)
                        val mapped = parts.map { it }
                        println(mapped.size)
                    }

            """,
            // testIsCheckWithStarProjectionDoesNotEmitErasureWarning
            """
            package sample11

                    fun f(x: Any): Boolean = x is List<*>
                    fun main(): Int = 0

            """,
            // testIsCheckWithReifiedTypeParameterDoesNotEmitNonReifiedDiagnostic
            """
            package sample12

                    inline fun <reified T> f(x: Any): Boolean = x is T
                    fun main(): Int = if (f<Int>(1)) 1 else 0

            """,
            // testConstValAcceptsNonNullableStringTypeAnnotation
            """
            package sample13

                    const val name: String = "ok"
                    fun main(): Int = 0

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFunctionTypeParameterWithUpperBound ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))
                let wrapSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "wrap" &&
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

            // === testReifiedInlineFunctionSupportsUnsafeCastAndBoundedTypeParameter ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let castSymbol = try #require(sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "castOrThrow"
                })
                let castSignature = try #require(sema.symbols.functionSignature(for: castSymbol.id))
                #expect(castSignature.reifiedTypeParameterIndices == Set([0]))
                #expect(castSignature.typeParameterSymbols.count == 1)

                let boundedSymbol = try #require(sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "boundedTypeName"
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
                        interner.intern("kotlin"),
                        interner.intern("Comparable"),
                    ]
                    let comparableSymbol = try #require(sema.symbols.lookup(fqName: comparableFQName))
                    #expect(classType.classSymbol == comparableSymbol)
                }

            }

            // === testTryCatchExpressionInference ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testTryCatchClauseBindingsResolvePrimitiveAndNominalTypes ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))
                let tryExprID = try #require(firstExprIDInPath(in: ast, path: sample3Path, ctx: ctx) { exprID, expr in
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
                    symbol.kind == .class && interner.resolve(symbol.name) == "MyError"
                }
                let resolvedCustomErrorSymbol = try #require(customErrorSymbol)
                guard case let .classType(customErrorType) = sema.types.kind(of: secondBinding.parameterType) else {
                    Issue.record("Expected nominal catch parameter type")
                    return
                }
                #expect(customErrorType.classSymbol == resolvedCustomErrorSymbol.id)
                #expect(sema.symbols.propertyType(for: secondBinding.parameterSymbol) == secondBinding.parameterType)

                let catchNameRef = try #require(firstExprIDInPath(in: ast, path: sample3Path, ctx: ctx) { exprID, expr in
                    guard case let .nameRef(name, _) = expr else {
                        return false
                    }
                    return interner.resolve(name) == "e"
                        && sema.bindings.identifierSymbol(for: exprID) == firstBinding.parameterSymbol
                })
                #expect(sema.bindings.identifierSymbol(for: catchNameRef) == firstBinding.parameterSymbol)
                #expect(sema.bindings.exprType(for: catchNameRef) == intType)

            }

            // === testTryCatchClauseBindingWithoutParameterDefaultsToAny ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))
                let tryExprID = try #require(firstExprIDInPath(in: ast, path: sample4Path, ctx: ctx) { exprID, expr in
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

            // === testTryCatchExpressionMatchesCompletionCriteriaExample ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sample5Diagnostics)

            }

            // === testTryCatchDefiniteInitializationMergesNormalBranches ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sample6Diagnostics)

            }

            // === testTryPartialCatchRethrowMergesOnlyNormalPaths ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sample7Diagnostics)

            }

            // === testTryFinallyReturnValueDoesNotPolluteTypeInference ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample8Diagnostics)

            }

            // === testSuspendFunctionSignature ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let delayedSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "delayed"
                }
                #expect(delayedSymbol != nil)
                if let sym = delayedSymbol,
                   let sig = sema.symbols.functionSignature(for: sym.id)
                {
                    #expect(sig.isSuspend)
                }

            }

            // === testStringSplitMarksCollectionForFallbackMembers ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample10Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample10Diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample10Diagnostics)

            }

            // === testIsCheckWithStarProjectionDoesNotEmitErasureWarning ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: sample11Diagnostics)

            }

            // === testIsCheckWithReifiedTypeParameterDoesNotEmitNonReifiedDiagnostic ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0084", in: sample12Diagnostics)

            }

            // === testConstValAcceptsNonNullableStringTypeAnnotation ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0082", in: sample13Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnosticsTryCatchInitializationAndIsCheckRules() throws {

        let sources: [String] = [
            // testUninitializedVariableUseEmitsDiagnostic
            """
            package sample0

                    fun main(): Int {
                        var x: Int
                        return x
                    }

            """,
            // testCompoundAssignOnUninitializedVariableEmitsDiagnostic
            """
            package sample1

                    fun main(): Int {
                        var x: Int
                        x += 1
                        return x
                    }

            """,
            // testIsCheckWithErasedGenericTypeEmitsWarning
            """
            package sample2

                    fun f(x: Any): Boolean = x is List<String>
                    fun main(): Int = 0

            """,
            // testIsCheckWithNonReifiedTypeParameterEmitsDiagnostic
            """
            package sample3

                    fun <T> f(x: Any): Boolean = x is T
                    fun main(): Int = 0

            """,
            // testConstValRejectsNullablePrimitiveTypeAnnotation
            """
            package sample4

                    const val maybeInt: Int? = 1
                    fun main(): Int = 0

            """,
            // testConstValRejectsNullableStringTypeAnnotation
            """
            package sample5

                    const val maybeName: String? = "ok"
                    fun main(): Int = 0

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testUninitializedVariableUseEmitsDiagnostic ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: sample0Diagnostics)

            }

            // === testCompoundAssignOnUninitializedVariableEmitsDiagnostic ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: sample1Diagnostics)

            }

            // === testIsCheckWithErasedGenericTypeEmitsWarning ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-ERASED-TYPE", in: sample2Diagnostics)

            }

            // === testIsCheckWithNonReifiedTypeParameterEmitsDiagnostic ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0084", in: sample3Diagnostics)

            }

            // === testConstValRejectsNullablePrimitiveTypeAnnotation ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0082", in: sample4Diagnostics)

            }

            // === testConstValRejectsNullableStringTypeAnnotation ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0082", in: sample5Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRCleanTryCatchInitializationAndIsCheckRules() throws {

        let sources: [String] = [
            // testDeferredInitializationViaIfElse
            """
            package sample0

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
            // testPrintlnBuiltinInfersUnit
            """
            package sample1

                    fun main() {
                        println("hello")
                        println()
                    }

            """,
            // testVarLocalReassignment
            """
            package sample2

                    fun main(): Int {
                        var x = 1
                        x = 10
                        return x
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testDeferredInitializationViaIfElse ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: sample0Diagnostics)

            }

            // === testPrintlnBuiltinInfersUnit ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testVarLocalReassignment ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sample2Diagnostics)

            }

        }
    }

}

#endif
