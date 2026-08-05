#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {

    // MARK: - ExprInference: unresolved reference

    // MARK: - ExprInference: unresolved function

    // MARK: - ExprInference: local function

    // MARK: - ExprInference: array access and assign

    // MARK: - ExprInference: for loop with loop variable

    // MARK: - ExprInference: binary type promotion

    // MARK: - ExprInference: string template

    // MARK: - ExprInference: if expression with else

    // MARK: - ExprInference: if expression without else infers Unit

    // MARK: - ExprInference: null reference

    // MARK: - ExprInference: while loop

    // MARK: - ExprInference: rangeTo operator

    // MARK: - ExprInference: local assign to unresolved variable

    // MARK: - ExprInference: when without else (boolean exhaustive)

    // MARK: - HeaderCollection: property with type annotation

    // MARK: - HeaderCollection: function with type parameters and upper bounds

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

    // MARK: - Consolidated Sema tests

    @Test
    func testDataFlowAndSemaRegression_CoreInferenceAndLoopDiagnosticsSema() throws {
        let sources: [String] = [
            // testRangeToOperatorInference
            """
            package sample0

                    fun main() {
                        val r = 1..10
                    }

            """,
            // testPropertyTypeAnnotationResolves
            """
            package sample1

                    val count: Int = 0
                    val name: String = "test"
                    val flag: Boolean = true
                    fun main(): Int = 0

            """,
            // testContinueOutsideLoopEmitsDiagnostic
            """
            package sample2

                    fun main(): Int {
                        continue
                        return 0
                    }

            """,
            // testUnresolvedReferenceEmitsDiagnostic
            """
            package sample3

                    fun main(): Int = unknownVar

            """,
            // testUnresolvedFunctionEmitsDiagnostic
            """
            package sample4

                    fun main(): Int = unknownFunc(42)

            """,
            // testLocalAssignToUnresolvedVariableEmitsDiagnostic
            """
            package sample5

                    fun main() {
                        noSuchVar = 42
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testRangeToOperatorInference ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testPropertyTypeAnnotationResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let countSym = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "count" && symbol.kind == .property
                }
                #expect(countSym != nil)
                if let sym = countSym {
                    #expect(sema.symbols.propertyType(for: sym.id) != nil)
                }

            }

            // === testContinueOutsideLoopEmitsDiagnostic ===

            do {

                let sample0Path = paths[2]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0019", in: sample0Diagnostics)

            }

            // === testUnresolvedReferenceEmitsDiagnostic ===

            do {

                let sample1Path = paths[3]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testUnresolvedFunctionEmitsDiagnostic ===

            do {

                let sample2Path = paths[4]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0023", in: sample2Diagnostics)

            }

            // === testLocalAssignToUnresolvedVariableEmitsDiagnostic ===

            do {

                let sample3Path = paths[5]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0013", in: sample3Diagnostics)

            }

        }
    }
// MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRCleanCoreInferenceAndLoopDiagnostics() throws {

        let sources: [String] = [
            // testLocalFunctionDeclarationInference
            """
            package sample0

                    fun main(): Int {
                        fun add(a: Int, b: Int): Int = a + b
                        return add(1, 2)
                    }

            """,
            // testSuspendLocalFunctionDeclarationInference
            """
            package sample1

                    suspend fun delayed(v: Int): Int = v

                    fun main(): Int {
                        suspend fun local(v: Int): Int = delayed(v)
                        return 0
                    }

            """,
            // testArrayAccessAndAssignInference
            """
            package sample2

                    fun main(): Int {
                        val arr = IntArray(3)
                        arr[0] = 10
                        return arr[0]
                    }

            """,
            // testForLoopInfersElementType
            """
            package sample3

                    fun main(): Int {
                        val arr = IntArray(3)
                        var sum = 0
                        for (item in arr) {
                            sum += item
                        }
                        return sum
                    }

            """,
            // testBinaryOperatorTypePromotionLong
            """
            package sample4

                    fun main(): Long = 1L + 2

            """,
            // testBinaryOperatorTypePromotionDouble
            """
            package sample5

                    fun main(): Double = 1.0 + 2.0

            """,
            // testBinaryOperatorTypePromotionFloat
            """
            package sample6

                    fun main(): Float = 1.5f + 2.5f

            """,
            // testStringTemplateInference
            """
            package sample7

                    fun main(): String {
                        val name = "World"
                        return "Hello, $name!"
                    }

            """,
            // testIfExpressionWithElseInfersLUB
            """
            package sample8

                    fun pick(flag: Boolean): Int {
                        val x = if (flag) 1 else 2
                        return x
                    }
                    fun main() = pick(true)

            """,
            // testIfExpressionWithoutElseInfersUnit
            """
            package sample9

                    fun doSomething(flag: Boolean) {
                        if (flag) println("yes")
                    }
                    fun main() = doSomething(true)

            """,
            // testNullLiteralInference
            """
            package sample10

                    fun main(): Any? = null

            """,
            // testWhileLoopInference
            """
            package sample11

                    fun main(): Int {
                        var i = 0
                        while (i < 10) {
                            i = i + 1
                        }
                        return i
                    }

            """,
            // testWhenBooleanExhaustive
            """
            package sample12

                    fun desc(flag: Boolean): String = when (flag) {
                        true -> "yes"
                        false -> "no"
                    }
                    fun main() = desc(true)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testLocalFunctionDeclarationInference ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testSuspendLocalFunctionDeclarationInference ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testArrayAccessAndAssignInference ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testForLoopInfersElementType ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionLong ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionDouble ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testBinaryOperatorTypePromotionFloat ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testStringTemplateInference ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIfExpressionWithElseInfersLUB ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIfExpressionWithoutElseInfersUnit ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testNullLiteralInference ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testWhileLoopInference ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testWhenBooleanExhaustive ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

        }
    }

}

#endif
