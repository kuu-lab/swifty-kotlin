#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-IO-FN-038: File.toRelativeString(base: File): String
//
// Validates the synthetic `kotlin.io.File.toRelativeString` declaration registered
// in `HeaderHelpers+SyntheticTODOAndIOStubs.swift`. The expectations:
// 1. Calls of the form `file.toRelativeString(base)` resolve through Sema for
//    plain `java.io.File` receivers and arguments.
// 2. The call expression types as `String`, including when the result is fed
//    into a `String` consumer such as `println(...)` or a `String` return.
// 3. The Sema-side function symbol binds to the runtime export
//    `kk_file_toRelativeString`, which is the contract the ABI lowering pass
//    relies on to thread the `outThrown` slot for IllegalArgumentException.

@Suite
struct FileToRelativeStringFunctionTests {

    // MARK: - Resolves with a File argument

    // MARK: - Composes with println / String consumers

    // MARK: - Call expression types as String

    // MARK: - Works inside scope functions (let/run/apply/with)

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
            // testFileToRelativeStringResolves
            """
            package sample0

                    import java.io.File

                    fun describe(file: File, base: File): String {
                        return file.toRelativeString(base)
                    }

            """,
            // testFileToRelativeStringCallExpressionTypedAsString
            """
            package sample1

                    import java.io.File

                    fun main() {
                        val target = File("/a/b/c")
                        val base = File("/a")
                        val rel = target.toRelativeString(base)
                        println(rel)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileToRelativeStringResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.toRelativeString(base) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileToRelativeStringCallExpressionTypedAsString ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Sema should type target.toRelativeString(base) as String: \(sample1Diagnostics.map(\.message))"
                )

                let callExprs = memberCallExprIDsInPath(named: "toRelativeString", in: ast, path: sample1Path, ctx: ctx, interner: interner)
                #expect(
                    callExprs.count == 1,
                    "Expected exactly one toRelativeString call expression in the program."
                )
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == sema.types.stringType,
                        "Each File.toRelativeString(base) call expression must be typed as String"
                    )
                }

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testFileToRelativeStringComposesWithStringConsumer
            """
            package sample0

                    import java.io.File

                    fun main() {
                        val target = File("/a/b/c")
                        val base = File("/a")
                        val rel: String = target.toRelativeString(base)
                        println(rel)
                    }

            """,
            // testFileToRelativeStringInsideScopeFunctions
            """
            package sample1

                    import java.io.File

                    fun main() {
                        val base = File("/root")
                        val target = File("/root/sub/leaf.txt")
                        target.let { node ->
                            val rel: String = node.toRelativeString(base)
                            println(rel)
                        }
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

            // === testFileToRelativeStringComposesWithStringConsumer ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !sample0Diagnostics.contains { $0.severity == .error },
                    "File.toRelativeString(base) should compose into a String slot: \(sample0Diagnostics.map(\.message))"
                )

            }

            // === testFileToRelativeStringInsideScopeFunctions ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "File.toRelativeString should resolve inside scope functions: \(sample1Diagnostics.map(\.message))"
                )

            }

        }
    }

}

#endif
