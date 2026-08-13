@testable import CompilerCore
import Foundation
import Testing

/// Verifies CharSequence?.isNullOrEmpty() (STDLIB-TEXT-FN-031) resolves cleanly
/// in Sema through bundled Kotlin source.
@Suite
struct StringIsNullOrEmptyFunctionTests {

    /// A bare null receiver should stay ambiguous because Kotlin stdlib also
    /// exposes Array/Collection/Map nullable-receiver isNullOrEmpty overloads.

    /// The compiler should not lower nullable-receiver isNullOrEmpty() to the legacy
    /// String runtime helper after migration to bundled Kotlin source.

    private func isNullOrEmptyCallIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == "isNullOrEmpty",
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            results.append(exprID)
        }
        return results
    }

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
            // testIsNullOrEmptyResolvesInSource
            """
            package sample0

                    fun classifyNullable(value: String?): Boolean {
                        return value.isNullOrEmpty()
                    }

                    fun classifyNonNull(value: String): Boolean {
                        return value.isNullOrEmpty()
                    }

            """,
            // testNullLiteralIsNullOrEmptyIsAmbiguous
            """
            package sample1

                    fun classify(): Boolean {
                        return null.isNullOrEmpty()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testIsNullOrEmptyResolvesInSource ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnosticSummary = sample0Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "Expected isNullOrEmpty to resolve cleanly, got: \(diagnosticSummary)"
                )

                let callIDs = isNullOrEmptyCallIDs(in: ast, path: sample0Path, ctx: ctx, interner: interner)
                #expect(callIDs.count == 2, "Expected calls for nullable and non-null receivers")
                for callID in callIDs {
                    let exprType = try #require(sema.bindings.exprTypes[callID])
                    #expect(
                        exprType == sema.types.booleanType,
                        "isNullOrEmpty should be typed as Boolean"
                    )
                }

            }

            // === testNullLiteralIsNullOrEmptyIsAmbiguous ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(sample1Diagnostics.contains { $0.severity == .error })
                #expect(
                    sample1Diagnostics.contains { diagnostic in
                        diagnostic.code == "KSWIFTK-SEMA-0003"
                    },
                    "Expected null.isNullOrEmpty() to match kotlinc ambiguity diagnostics"
                )

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testIsNullOrEmptyDoesNotLowerToLegacyRuntimeHelper
            """
            package sample0

                    fun main() {
                        val maybe: String? = null
                        maybe.isNullOrEmpty()
                        val present: String? = ""
                        present.isNullOrEmpty()
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

            // === testIsNullOrEmptyDoesNotLowerToLegacyRuntimeHelper ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                try LoweringPhase().run(ctx)

                let body = try findKIRFunctionBody(named: "main", in: module, interner: interner)
                let throwFlags = extractThrowFlags(from: body, interner: interner)
                #expect(throwFlags["kk_string_isNullOrEmpty"] == nil)
                #expect(throwFlags["kk_string_isNullOrEmpty_flat"] == nil)
                #expect(throwFlags["__string_isNullOrEmpty_flat"] == nil)

            }

        }
    }

}
