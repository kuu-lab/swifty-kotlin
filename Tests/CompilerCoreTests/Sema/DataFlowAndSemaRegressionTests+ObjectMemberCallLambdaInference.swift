#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Object member call trailing-lambda inference

// Targets: TypeCheck/CallTypeChecker+MemberCallInferenceContext.swift

extension DataFlowAndSemaRegressionTests {

    // DEBT-DIFF-006: a named `object`'s member function taking a lambda
    // parameter (e.g. `(Foo) -> Foo`) failed to infer the lambda's parameter
    // type when called via a trailing lambda literal. Root cause:
    // tryInferFQNPackageTopLevelCall misidentified `SomeObject.member(...)`
    // as a package-qualified top-level call (like `kotlin.math.abs(x)`)
    // whenever a symbol happened to be registered under the same
    // owner-FQName + member-name path, and that fallback infers every
    // argument eagerly with no expected type — leaving the lambda's `it`/
    // named parameters unresolved.

    // Same bug reached with an implicit single-parameter lambda (`it`) and a
    // primitive receiver type, which fails earlier (at `it` itself) than the
    // data-class-copy case above.

    // A class instance (as opposed to an object singleton) already worked
    // before the fix; kept here as a same-shape control so a future change
    // can't silently regress this case while "fixing" the object case.

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
    func testRunSemaCleanObjectMemberCallLambdaInference() throws {

        let sources: [String] = [
            // testObjectMemberFunctionInfersTrailingLambdaParameterType
            """
            package sample0

                    data class Foo(val x: Int)

                    object Registry {
                        fun update(block: (Foo) -> Foo): Foo = block(Foo(0))
                    }

                    fun main() {
                        println(Registry.update { m -> m.copy(x = m.x + 1) }.x)
                    }

            """,
            // testObjectMemberFunctionInfersImplicitItParameterType
            """
            package sample1

                    object Registry {
                        fun update(block: (Int) -> Int): Int = block(5)
                    }

                    fun main() {
                        println(Registry.update { it + 1 })
                    }

            """,
            // testClassInstanceMemberFunctionInfersTrailingLambdaParameterType
            """
            package sample2

                    data class Foo(val x: Int)

                    class Registry {
                        fun update(block: (Foo) -> Foo): Foo = block(Foo(0))
                    }

                    fun main() {
                        println(Registry().update { m -> m.copy(x = m.x + 1) }.x)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testObjectMemberFunctionInfersTrailingLambdaParameterType ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(sample0Diagnostics.isEmpty, "Unexpected diagnostics: \(sample0Diagnostics.map(\.code))")

            }

            // === testObjectMemberFunctionInfersImplicitItParameterType ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(sample1Diagnostics.isEmpty, "Unexpected diagnostics: \(sample1Diagnostics.map(\.code))")

            }

            // === testClassInstanceMemberFunctionInfersTrailingLambdaParameterType ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(sample2Diagnostics.isEmpty, "Unexpected diagnostics: \(sample2Diagnostics.map(\.code))")

            }

        }
    }

}

#endif
