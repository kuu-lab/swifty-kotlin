#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-037: `fun java.io.File.startsWith(other: File): Boolean`
///                   `fun java.io.File.startsWith(other: String): Boolean`
///
/// Verifies that the synthetic `startsWith` overloads registered on the
/// `java.io.File` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticTODOAndIOStubs.swift`)
/// resolve through Sema for plain File receivers and bind to the runtime
/// helpers `kk_file_startsWith_file` / `kk_file_startsWith_string` listed in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct FileStartsWithFunctionTests {

    // KSP-483: `startsWith` is now also used internally by the bundled
    // `Stdlib/kotlin/io/Files.kt` (as `String.startsWith`), so member-call
    // scans across the whole AST must exclude bundled-stdlib files or they'll
    // pick up those internal calls alongside the user source's calls.
    private func memberCallExprIDs(
        named name: String,
        receiverType: TypeID,
        in ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceManager: SourceManager,
        path: String? = nil
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(receiver, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  sema.bindings.exprTypes[receiver] == receiverType,
                  !sourceManager.path(of: range.start.file).hasPrefix("__bundled_"),
                  path == nil || sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - File overload resolves cleanly

    // MARK: - String overload resolves cleanly

    // MARK: - Both call expressions are typed as Boolean

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
            // testFileStartsWithFileOverloadResolves
            """
            package sample0

                    import java.io.File

                    fun isChild(child: File, parent: File): Boolean {
                        return child.startsWith(parent)
                    }

                    fun main() {
                        println(isChild(File("/tmp/sub/file.txt"), File("/tmp")))
                    }

            """,
            // testFileStartsWithStringOverloadResolves
            """
            package sample1

                    import java.io.File

                    fun isUnderTmp(file: File): Boolean {
                        return file.startsWith("/tmp")
                    }

                    fun main() {
                        println(isUnderTmp(File("/tmp/sub/file.txt")))
                    }

            """,
            // testFileStartsWithCallExpressionsAreTypedAsBoolean
            """
            package sample2

                    import java.io.File

                    fun decide(file: File, parent: File): Boolean {
                        val a: Boolean = file.startsWith(parent)
                        val b: Boolean = file.startsWith("/tmp")
                        return a && b
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testFileStartsWithFileOverloadResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.startsWith(File) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileStartsWithStringOverloadResolves ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "File.startsWith(String) should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testFileStartsWithCallExpressionsAreTypedAsBoolean ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    !sample2Diagnostics.contains { $0.severity == .error },
                    "File.startsWith call expressions should type cleanly as Boolean: \(sample2Diagnostics.map(\.message))"
                )

                let booleanType = sema.types.booleanType

                let fileSymbol = try #require(
                    sema.symbols.lookup(fqName: ["java", "io", "File"].map(interner.intern))
                )
                let fileType = sema.types.make(
                    .classType(ClassType(classSymbol: fileSymbol, args: [], nullability: .nonNull))
                )
                let callExprs = memberCallExprIDs(
                    named: "startsWith",
                    receiverType: fileType,
                    in: ast,
                    sema: sema,
                    interner: interner,
                    sourceManager: ctx.sourceManager,
                    path: sample2Path
                )
                #expect(callExprs.count == 2, "expected two startsWith member calls")
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == booleanType,
                        "Each File.startsWith(...) call expression must be typed as Boolean"
                    )
                }

            }

        }
    }

}

#endif
