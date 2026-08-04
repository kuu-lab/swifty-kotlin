#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-CAP-008: generic receiver `T.() -> Unit` lambdas must be type-checked
/// with the concrete call-site receiver type substituted for `T`, so that
/// unqualified member access in the lambda body resolves against the actual
/// receiver and assignments to `var` properties do not trigger a false-positive
/// `KSWIFTK-SEMA-0014`.
@Suite
struct GenericReceiverLambdaTypeInferenceTests {

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
            // testGenericExtensionReceiverLambdaResolvesMembers
            """
            package sample0

                    val myValue: String = "lexical"

                    class MutableBox<T> {
                        var myValue: T? = null
                    }

                    fun <T> T.apply2(block: T.() -> Unit): T {
                        block()
                        return this
                    }

                    fun useApply2(): MutableBox<Int> = MutableBox<Int>().apply2 { myValue = 42 }

                    fun useApply2WithLexicalShadow(): MutableBox<Int> = MutableBox<Int>().apply2 { myValue = 42 }

            """,
            // testGenericRunWithReturnTypeResolvesMembers
            """
            package sample1

                    class MutableBox<T> {
                        var myValue: T? = null
                    }

                    fun <T, R> T.run2(block: T.() -> R): R = block()

                    fun useRun2(): Int = MutableBox<Int>().run2 {
                        myValue = 100
                        myValue ?: 0
                    }

            """,
            // testWithInferredReceiverFromArgumentStillWorks
            """
            package sample2

                    class MutableBox<T> {
                        var myValue: T? = null
                    }

                    fun <T, R> with2(receiver: T, block: T.() -> R): R = receiver.block()

                    fun useWith2(): Int {
                        val box = MutableBox<Int>()
                        return with2(box) {
                            myValue = 99
                            myValue ?: 0
                        }
                    }

            """,
            // testConcreteReceiverLambdaStillWorks
            """
            package sample3

                    class ConcreteBox {
                        var myValue: Int? = null
                    }

                    fun ConcreteBox.apply2(block: ConcreteBox.() -> Unit): ConcreteBox {
                        block()
                        return this
                    }

                    fun useConcrete(): ConcreteBox = ConcreteBox().apply2 { myValue = 42 }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testGenericExtensionReceiverLambdaResolvesMembers ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Generic receiver lambda should resolve members and shadow lexical myValue, got: \(errors)"
                )

            }

            // === testGenericRunWithReturnTypeResolvesMembers ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Generic receiver lambda T.() -> R should resolve myValue and return type, got: \(sample1Diagnostics)"
                )

            }

            // === testWithInferredReceiverFromArgumentStillWorks ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "with(receiver, T.() -> R) should resolve receiver members, got: \(sample2Diagnostics)"
                )

            }

            // === testConcreteReceiverLambdaStillWorks ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "Concrete receiver lambda should still resolve members, got: \(sample3Diagnostics)"
                )

            }

        }
    }

}

#endif
