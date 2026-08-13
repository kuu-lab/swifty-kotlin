#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntersectionTypeFlowTests {

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
            // testIntersectionWithAnyMakesTypeParamDefinitelyNonNull
            """
            package sample0

                    fun <T : Any?> identity(x: T & Any): T & Any = x

            """,
            // testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls
            """
            package sample1

                    fun Any.id(): Int = 1

                    fun <T : Any?> direct(x: T & Any): Int = x.id()
                    fun <T : Any?> safe(x: T & Any): Int? = x?.id()

            """,
            // testIntersectionParameterInferenceAtCallSite
            """
            package sample2

                    fun Any.idTag(): Int = 7

                    fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
                    fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()

                    fun main() {
                        println(directValue("hello"))
                        println(safeValue("world"))
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testIntersectionWithAnyMakesTypeParamDefinitelyNonNull ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let source = sources[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // Exclude bundled stdlib source (e.g. kotlin.random.Random's own `x`
                // field, KSP-466) so this only matches the test's own fixture,
                // regardless of how many other `x`-named declarations the stdlib has.
                let xRef = try #require(firstExprIDInPath(in: ast, path: sample0Path, ctx: ctx) { exprID, expr in
                    guard case let .nameRef(name, _) = expr,
                          interner.resolve(name) == "x",
                          let range = ast.arena.exprRange(exprID)
                    else { return false }
                    return !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
                })
                let xType = try #require(sema.bindings.exprType(for: xRef))

                guard case let .intersection(parts) = sema.types.kind(of: xType) else {
                    Issue.record("Expected intersection type for `x`, got \(sema.types.kind(of: xType))")
                    return
                }

                let hasAny = parts.contains { sema.types.kind(of: $0) == .any(.nonNull) }
                let hasTypeParam = parts.contains {
                    if case .typeParam = sema.types.kind(of: $0) {
                        return true
                    }
                    return false
                }

                #expect(hasAny)
                #expect(hasTypeParam)
                #expect(sema.types.isDefinitelyNonNull(xType))
                #expect(sema.types.nullability(of: xType) == .nonNull)
                #expect(!sample0Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample0Diagnostics.map(\.code))")

            }

            // === testDefinitelyNonNullIntersectionReceiverSupportsDirectAndSafeCalls ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let directCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "id"
                })
                let safeCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .safeMemberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "id"
                })

                #expect(sema.bindings.exprType(for: directCall) == sema.types.intType)
                #expect(
                    sema.bindings.exprType(for: safeCall) == sema.types.makeNullable(sema.types.intType)
                )
                #expect(!sample1Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample1Diagnostics.map(\.code))")

            }

            // === testIntersectionParameterInferenceAtCallSite ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample2Diagnostics)
                #expect(!sample2Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample2Diagnostics.map(\.code))")

            }

        }
    }

}

#endif
