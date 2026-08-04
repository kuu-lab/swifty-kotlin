#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - List<String> + String plus-operator inference

// Targets: TypeCheck/ExprTypeChecker+BinaryAndFlowInference.swift

extension DataFlowAndSemaRegressionTests {

    // DEBT-DIFF-006: `someList + "x"` where someList is a List<String> was
    // misinterpreted as string concatenation (`Any.toString() + String`)
    // whenever the RHS happened to be a String, because the string-concat
    // short-circuit (`isString(lhs) || isString(rhs)`) ran before the
    // List/Sequence plus/minus fallback check. This is a plain type-inference
    // bug, independent of data classes, `copy()`, or objects: any
    // `List<String> + String` expression (element type coincides with the
    // RHS's type) was affected. Fixed by reordering the two checks so the
    // collection fallback (which only looks at the LHS's static type) runs
    // first.

    // Same bug via a literal receiver and no intermediate local, matching the
    // exact shape that reaches `PluginRegistry.update`'s lambda body in
    // Scripts/diff_cases/compiler_plugin_api.kt (`m.registeredExtensions +
    // "$kind:$name"`, `m.generatedModules + moduleName`, etc.).

    // Control: `Int + String` (never valid in real Kotlin) is unrelated to
    // this fix and must keep behaving exactly as before — the fix only
    // reorders the check relative to List/Sequence-typed receivers, primitive
    // receivers never enter that branch.

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
    func testRunSemaCleanListStringPlusOperatorInference() throws {

        let sources: [String] = [
            // testListOfStringPlusStringInfersListNotString
            """
            package sample0

                    fun main() {
                        val items: List<String> = listOf("a", "b")
                        val x: List<String> = items + "x"
                        println(x)
                    }

            """,
            // testDataClassCopyWithListPlusStringNamedArgument
            """
            package sample1

                    data class Meta(val tags: List<String> = emptyList())

                    fun addTag(meta: Meta, tag: String): Meta =
                        meta.copy(tags = meta.tags + tag)

                    fun main() {
                        println(addTag(Meta(), "x").tags)
                    }

            """,
            // testStringConcatenationStillInfersStringForNonListReceiver
            """
            package sample2

                    fun main() {
                        val greeting: String = "hi" + "there"
                        println(greeting)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testListOfStringPlusStringInfersListNotString ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(sample0Diagnostics.isEmpty, "Unexpected diagnostics: \(sample0Diagnostics.map(\.code))")

            }

            // === testDataClassCopyWithListPlusStringNamedArgument ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(sample1Diagnostics.isEmpty, "Unexpected diagnostics: \(sample1Diagnostics.map(\.code))")

            }

            // === testStringConcatenationStillInfersStringForNonListReceiver ===

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
