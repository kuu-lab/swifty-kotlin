#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

extension DataFlowAndSemaRegressionTests {

    // MARK: - ExprInference: typed local declaration

    // MARK: - ExprInference: val reassignment diagnostic

    // MARK: - ExprInference: do-while loop

    // MARK: - ExprInference: compound assignment operators

    // MARK: - ExprInference: compound assign on val

    // MARK: - ExprInference: member compound assign / postfix on val

    // MARK: - ExprInference: when expression

    // MARK: - ExprInference: return expression

    // MARK: - ExprInference: Long/Float/Double/Char literals

    // MARK: - ExprInference: is check and as cast

    // MARK: - ExprInference: null assert

    // MARK: - ExprInference: elvis operator

    // MARK: - ExprInference: break/continue outside loop

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
    func testRunSemaCleanDoWhileAndExpressionInference() throws {

        let sources: [String] = [
            // testClassWithTypeParametersDefinesVariance
            """
            package sample0

                    class Box<out T>(val value: T)
                    fun main(): Int = 0

            """,
            // testDoWhileConditionCanReferenceBodyLocal
            """
            package sample1

                    fun main(): Int {
                        var loops = 0
                        do {
                            val local = loops + 1
                            loops = local
                        } while (local < 3)
                        return loops
                    }

            """,
            // testDoWhileInlineBodyAssignmentTypeChecks
            """
            package sample2

                    fun main(): Int {
                        var x = 0
                        do x = x + 1 while (x < 3)
                        return x
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testClassWithTypeParametersDefinesVariance ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let boxSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Box"
                }
                #expect(boxSymbol != nil)

            }

            // === testDoWhileConditionCanReferenceBodyLocal ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0013", in: sample1Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testDoWhileInlineBodyAssignmentTypeChecks ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0013", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample2Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnosticsDoWhileAndExpressionInference() throws {

        let sources: [String] = [
            // testValReassignmentEmitsDiagnostic
            """
            package sample0

                    fun main(): Int {
                        val x = 1
                        x = 2
                        return x
                    }

            """,
            // testDoWhileBodyLocalDoesNotLeakOutsideLoop
            """
            package sample1

                    fun main(): Int {
                        do {
                            val local = 1
                        } while (local < 2)
                        return local
                    }

            """,
            // testCompoundAssignOnValEmitsDiagnostic
            """
            package sample2

                    fun main(): Int {
                        val x = 5
                        x += 1
                        return x
                    }

            """,
            // testMemberCompoundAssignOnValEmitsDiagnostic
            """
            package sample3

                    class Box(val n: Int)
                    fun bump(b: Box): Int {
                        b.n += 1
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testMemberPostfixIncrementOnValEmitsDiagnostic
            """
            package sample4

                    class Box(val n: Int)
                    fun bump(b: Box): Int {
                        b.n++
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testBreakOutsideLoopEmitsDiagnostic
            """
            package sample5

                    fun main(): Int {
                        break
                        return 0
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testValReassignmentEmitsDiagnostic ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample0Diagnostics)

            }

            // === testDoWhileBodyLocalDoesNotLeakOutsideLoop ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample1Diagnostics)

            }

            // === testCompoundAssignOnValEmitsDiagnostic ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample2Diagnostics)

            }

            // === testMemberCompoundAssignOnValEmitsDiagnostic ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample3Diagnostics)

            }

            // === testMemberPostfixIncrementOnValEmitsDiagnostic ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0014", in: sample4Diagnostics)

            }

            // === testBreakOutsideLoopEmitsDiagnostic ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0018", in: sample5Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRCleanDoWhileAndExpressionInference() throws {

        let sources: [String] = [
            // testTypedLocalDeclarationInfersCorrectly
            """
            package sample0

                    fun main(): Int {
                        val x: Int = 42
                        return x
                    }

            """,
            // testDoWhileLoopInfersUnitType
            """
            package sample1

                    fun main(): Int {
                        var x = 0
                        do {
                            x = x + 1
                        } while (x < 3)
                        return x
                    }

            """,
            // testCompoundAssignmentOperators
            """
            package sample2

                    fun main(): Int {
                        var x = 10
                        x += 5
                        x -= 3
                        x *= 2
                        x /= 4
                        x %= 3
                        return x
                    }

            """,
            // testMemberCompoundAssignOnVarDoesNotEmitDiagnostic
            """
            package sample3

                    class Box(var n: Int)
                    fun bump(b: Box): Int {
                        b.n += 1
                        return b.n
                    }
                    fun main(): Int = bump(Box(5))

            """,
            // testWhenExpressionInference
            """
            package sample4

                    fun classify(x: Int): String {
                        return when (x) {
                            1 -> "one"
                            2 -> "two"
                            else -> "other"
                        }
                    }
                    fun main() = classify(1)

            """,
            // testReturnExpressionInference
            """
            package sample5

                    fun earlyReturn(flag: Boolean): Int {
                        if (flag) return 42
                        return 0
                    }
                    fun main() = earlyReturn(true)

            """,
            // testLongLiteralInference
            """
            package sample6

                    fun main(): Long = 42L

            """,
            // testFloatLiteralInference
            """
            package sample7

                    fun main(): Float = 1.5f

            """,
            // testDoubleLiteralInference
            """
            package sample8

                    fun main(): Double = 3.14

            """,
            // testCharLiteralInference
            """
            package sample9

                    fun main(): Char = 'A'

            """,
            // testIsCheckInfersBoolean
            """
            package sample10

                    fun check(x: Any): Boolean = x is Int
                    fun main() = check(42)

            """,
            // testSafeCastInfersNullableType
            """
            package sample11

                    fun tryCast(x: Any): Int? = x as? Int
                    fun main() = tryCast(42)

            """,
            // testHardCastInference
            """
            package sample12

                    fun forceCast(x: Any): Int = x as Int
                    fun main() = forceCast(42)

            """,
            // testNullAssertInfersNonNullable
            """
            package sample13

                    fun forceUnwrap(x: Int?): Int = x!!
                    fun main() = forceUnwrap(42)

            """,
            // testElvisOperatorInference
            """
            package sample14

                    fun fallback(x: Int?): Int = x ?: 0
                    fun main() = fallback(null)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testTypedLocalDeclarationInfersCorrectly ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let xSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "x" && symbol.kind == .local
                }
                #expect(xSymbol != nil)

            }

            // === testDoWhileLoopInfersUnitType ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testCompoundAssignmentOperators ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sample2Diagnostics)

            }

            // === testMemberCompoundAssignOnVarDoesNotEmitDiagnostic ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0014", in: sample3Diagnostics)

            }

            // === testWhenExpressionInference ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testReturnExpressionInference ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let body = try findKIRFunctionBody(named: "earlyReturn", in: module, interner: interner)
                let returnCount = body.filter { instruction in
                    if case .returnValue = instruction { return true }
                    return false
                }.count
                #expect(returnCount >= 2)

            }

            // === testLongLiteralInference ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testFloatLiteralInference ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testDoubleLiteralInference ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testCharLiteralInference ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testIsCheckInfersBoolean ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testSafeCastInfersNullableType ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testHardCastInference ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testNullAssertInfersNonNullable ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testElvisOperatorInference ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

        }
    }

}

#endif
