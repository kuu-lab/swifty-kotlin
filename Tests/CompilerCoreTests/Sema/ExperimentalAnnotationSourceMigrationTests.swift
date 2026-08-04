#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// KSP-668: `kotlin.experimental.ExperimentalTypeInference` and
/// `kotlin.experimental.ExperimentalNativeApi` are now declared by bundled
/// Kotlin source instead of synthetic stubs. These tests lock in that the
/// markers still resolve and that `ExperimentalNativeApi` keeps its
/// `@RequiresOptIn` opt-in behavior.
@Suite
struct ExperimentalAnnotationSourceMigrationTests {

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
            // testExperimentalTypeInferenceResolvesAsTypeViaImport
            """
            package sample0

                    import kotlin.experimental.ExperimentalTypeInference

                    fun marker(x: ExperimentalTypeInference?): Int = 0

            """,
            // testExperimentalTypeInferenceResolvesAsTypeViaFQN
            """
            package sample1

                    fun marker(x: kotlin.experimental.ExperimentalTypeInference?): Int = 0

            """,
            // testExperimentalNativeApiResolvesAsType
            """
            package sample2

                    import kotlin.experimental.ExperimentalNativeApi

                    fun marker(x: ExperimentalNativeApi?): Int = 0

            """,
            // testExperimentalNativeApiResolvesFromBundledSource
            """
            package sample3

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun demo() {}

            """,
            // testExperimentalNativeApiRequiresOptInWhenUsed
            """
            package sample4

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun useIt(): Int = experimentalApi()

            """,
            // testExperimentalNativeApiOptInSuppressesError
            """
            package sample5

                    @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

                    @kotlin.experimental.ExperimentalNativeApi
                    fun experimentalApi(): Int = 42

                    fun useIt(): Int = experimentalApi()

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testExperimentalTypeInferenceResolvesAsTypeViaImport ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = sample0Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalTypeInference to resolve as a type via import, got: \(diagnostics)"
                )

            }

            // === testExperimentalTypeInferenceResolvesAsTypeViaFQN ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = sample1Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalTypeInference to resolve as a type via FQN, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiResolvesAsType ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let diagnostics = sample2Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "Expected ExperimentalNativeApi to resolve as a type via import, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiResolvesFromBundledSource ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let diagnostics = sample3Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample3Diagnostics.contains { $0.severity == .error },
                    "Expected marking an API with ExperimentalNativeApi to succeed, got: \(diagnostics)"
                )

            }

            // === testExperimentalNativeApiRequiresOptInWhenUsed ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    sample4Diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
                    "Expected an opt-in error when using ExperimentalNativeApi without opt-in"
                )

            }

            // === testExperimentalNativeApiOptInSuppressesError ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let diagnostics = sample5Diagnostics.map { "\($0.code): \($0.message)" }

                #expect(
                    !sample5Diagnostics.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" },
                    "Expected opt-in to suppress the ExperimentalNativeApi error, got: \(diagnostics)"
                )

            }

        }
    }

}

#endif
