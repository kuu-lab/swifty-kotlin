#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct FlowSemaTests {

    // MARK: - TYPE-113: Flow<T> type preservation tests

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
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testFlowBuilderAndChainTypeChecks
            """
            package sample0

                    fun main() {
                        runBlocking {
                            flow {
                                emit(1)
                                emit(2)
                            }.map { it * 2 }
                                .collect { println(it) }
                        }
                    }

            """,
            // testRunBlockingLambdaAvoidsTypeConstraintFailure
            """
            package sample1

                    fun main() {
                        runBlocking {
                            println(1)
                        }
                    }

            """,
            // testFlowMapCallableReferenceDoesNotOverConstrain
            """
            package sample2

                    fun twice(x: Int): Int = x * 2

                    fun main() {
                        runBlocking {
                            flow {
                                emit(1)
                                emit(2)
                            }.map(::twice)
                                .collect { println(it) }
                        }
                    }

            """,
            // testFlowStoredInLocalVariableKeepsFlowReceiverTyping
            """
            package sample3

                    fun main() {
                        runBlocking {
                            val stream = flow {
                                emit(1)
                                emit(2)
                            }.map { it * 2 }
                            stream.collect { println(it) }
                            stream.collect { println(it) }
                        }
                    }

            """,
            // testFlowFallbackDoesNotApplyToArbitraryAnyReceiver
            """
            package sample4

                    fun main() {
                        val value: Any = 1
                        value.map { it }
                    }

            """,
            // testUserDefinedFlowFunctionShadowsBuiltinFlowFallback
            """
            package sample5

                    fun flow(block: () -> Int): Int = block()

                    fun main() {
                        val x: Int = flow { 1 }
                        println(x)
                    }

            """,
            // testFlowBuilderExprTypeIsFlowClassType
            """
            package sample6

                    fun main() {
                        runBlocking {
                            val f = flow { emit(1) }
                            f.collect { println(it) }
                        }
                    }

            """,
            // testFlowMapResultTypeIsFlowClassType
            """
            package sample7

                    fun main() {
                        runBlocking {
                            val mapped = flow { emit(1) }.map { it * 2 }
                            mapped.collect { println(it) }
                        }
                    }

            """,
            // testFlowFilterPreservesElementType
            """
            package sample8

                    fun main() {
                        runBlocking {
                            val f = flow { emit(1); emit(2) }.filter { it > 1 }
                            f.collect { println(it) }
                        }
                    }

            """,
            // testFlowTakeResultTypeIsFlowClassType
            """
            package sample9

                    fun main() {
                        runBlocking {
                            val taken = flow { emit(1); emit(2); emit(3) }.take(2)
                            taken.collect { println(it) }
                        }
                    }

            """,
            // testAdditionalFlowBuildersTypeCheck
            """
            package sample10

                    import kotlinx.coroutines.*
                    import kotlinx.coroutines.flow.*

                    fun main() {
                        runBlocking {
                            flowOf(1, 2, 3).collect { println(it) }
                            emptyFlow<Int>().collect { println(it) }
                            listOf(1, 2, 3).asFlow().collect { println(it) }
                            channelFlow<Int> { emit(1); emit(2) }.collect { println(it) }
                            callbackFlow<Int> { emit(3); emit(4) }.collect { println(it) }
                        }
                    }

            """,
            // testFlowErrorHandlingMembersTypeCheck
            """
            package sample11

                    fun failOnTwo(value: Int): Int {
                        if (value == 2) throw RuntimeException("boom")
                        return value
                    }

                    fun failAlways(value: Int): Int {
                        throw RuntimeException("retry")
                    }

                    fun main() {
                        runBlocking {
                            flow {
                                emit(1)
                                emit(2)
                            }.map(::failOnTwo)
                                .catch { _: Throwable -> println(-1) }
                                .collect { value: Int -> println(value) }

                            val retried = flow {
                                emit(10)
                                emit(20)
                            }.map(::failOnTwo)
                                .retry(1)
                            println(retried.toList())

                            val retriedWhen = flow {
                                emit(7)
                            }.map(::failAlways)
                                .retryWhen { _: Throwable, attempt: Long -> attempt < 1L }
                            println(retriedWhen.toList())
                        }
                    }

            """,
            // testUserDefinedEmitInsideFlowBuilderShadowsBuiltinEmitFallback
            """
            package sample12

                    fun main() {
                        runBlocking {
                            flow {
                                val emit = { x: Int -> x + 1 }
                                val y: Int = emit(1)
                                println(y)
                            }.collect { println(it) }
                        }
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFlowBuilderAndChainTypeChecks ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample0Diagnostics)

            }

            // === testRunBlockingLambdaAvoidsTypeConstraintFailure ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample1Diagnostics)

            }

            // === testFlowMapCallableReferenceDoesNotOverConstrain ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample2Diagnostics)

            }

            // === testFlowStoredInLocalVariableKeepsFlowReceiverTyping ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample3Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sample3Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample3Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample3Diagnostics)

            }

            // === testFlowFallbackDoesNotApplyToArbitraryAnyReceiver ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let hasExpectedDiagnostic = sample4Diagnostics.contains(where: {
                    ["KSWIFTK-SEMA-0002", "KSWIFTK-SEMA-0024"].contains($0.code)
                })
                #expect(
                    hasExpectedDiagnostic,
                    "Expected unresolved member diagnostic for non-flow Any receiver. Got: \(sample4Diagnostics.map(\.code))"
                )

            }

            // === testUserDefinedFlowFunctionShadowsBuiltinFlowFallback ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample5Diagnostics)

            }

            // === testFlowBuilderExprTypeIsFlowClassType ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample6Diagnostics)

                // Find the flow expression and verify its type is Flow<...> (a classType),
                // not Any.
                let flowExprs = sema.bindings.flowExprIDs
                #expect(!flowExprs.isEmpty, "Should have at least one flow expression")

                for flowExpr in flowExprs {
                    guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                    // The expression type should NOT be anyType or nullableAnyType
                    #expect(exprType != sema.types.anyType,
                        "Flow expression type should not be erased to Any")
                    #expect(exprType != sema.types.nullableAnyType,
                        "Flow expression type should not be erased to Any?")
                    // It should be a classType (Flow<...>)
                    if case .classType(let classType) = sema.types.kind(of: exprType) {
                        let symbol = sema.symbols.symbol(classType.classSymbol)
                        let name = symbol.map { interner.resolve($0.name) }
                        #expect(name == "Flow", "Flow expression should have Flow class type")
                        #expect(!classType.args.isEmpty, "Flow type should have type arguments")
                    }
                }

            }

            // === testFlowMapResultTypeIsFlowClassType ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample7Diagnostics)

                // The map result should also be a flow expression with a non-Any type
                let flowExprs = sema.bindings.flowExprIDs
                #expect(flowExprs.count >= 2,
                    "Should have flow builder + map as flow expressions")

                for flowExpr in flowExprs {
                    guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                    #expect(exprType != sema.types.anyType,
                        "Flow chain result should not be erased to Any")
                }

            }

            // === testFlowFilterPreservesElementType ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample8Diagnostics)

                let flowExprs = sema.bindings.flowExprIDs
                #expect(flowExprs.count >= 2,
                    "Should have flow builder + filter as flow expressions")
                // At least one flow expression (the filter result) should track element type
                let exprsWithElementType = flowExprs.filter { sema.bindings.flowElementType(forExpr: $0) != nil }
                #expect(!exprsWithElementType.isEmpty,
                    "At least one flow expression should track element type after filter")

            }

            // === testFlowTakeResultTypeIsFlowClassType ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample9Diagnostics)

                let flowExprs = sema.bindings.flowExprIDs
                for flowExpr in flowExprs {
                    guard let exprType = sema.bindings.exprType(for: flowExpr) else { continue }
                    #expect(exprType != sema.types.anyType,
                        "Flow.take() result should not be erased to Any")
                }

            }

            // === testAdditionalFlowBuildersTypeCheck ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample10Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample10Diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample10Diagnostics)

            }

            // === testFlowErrorHandlingMembersTypeCheck ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample11Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0003", in: sample11Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample11Diagnostics)
                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample11Diagnostics)

            }

            // === testUserDefinedEmitInsideFlowBuilderShadowsBuiltinEmitFallback ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample12Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample12Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sample12Diagnostics)

            }

        }
    }

}

#endif
