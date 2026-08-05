@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-IO-FN-035: `fun java.net.URL.readText(): String`
///
/// Verifies that the synthetic `readText` member registered on the
/// `java.net.URL` synthetic class (see
/// `Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticURLStubs.swift`)
/// resolves through Sema for plain URL receivers and binds to the runtime
/// helper `kk_url_readText` listed in
/// `Sources/RuntimeABI/RuntimeABISpec+FileIO.swift`.
@Suite
struct URLReadTextFunctionTests {

    private func memberCallExprIDs(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    // MARK: - readText() resolves cleanly on a URL receiver

    // MARK: - readText() call expression is typed as String

    // MARK: - Sema registers readText with the expected runtime link name

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
            // testURLReadTextResolves
            """
            package sample0

                    import java.net.URL

                    fun fetchContent(url: URL): String {
                        return url.readText()
                    }

                    fun main() {
                        val url = URL("file:///tmp/test.txt")
                        println(fetchContent(url))
                    }

            """,
            // testURLReadTextCallExpressionIsTypedAsString
            """
            package sample1

                    import java.net.URL

                    fun readContent(url: URL): String {
                        val text: String = url.readText()
                        return text
                    }

            """,
            // testURLReadTextSignatureAndRuntimeLinkName
            """
            package sample2
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testURLReadTextResolves ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "URL.readText() should resolve cleanly, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

            }

            // === testURLReadTextCallExpressionIsTypedAsString ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "URL.readText() call expression should type cleanly as String: \(sample1Diagnostics.map(\.message))"
                )

                let callExprs = memberCallExprIDsInPath(named: "readText", in: ast, path: sample1Path, ctx: ctx, interner: interner)
                #expect(callExprs.count == 1, "expected one readText member call")
                for callExpr in callExprs {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == sema.types.stringType,
                        "URL.readText() call expression must be typed as String"
                    )
                }

            }

            // === testURLReadTextSignatureAndRuntimeLinkName ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let symbols = sema.symbols
                let types = sema.types

                let urlSymbol = try #require(
                    symbols.lookup(fqName: ["java", "net", "URL"].map(interner.intern))
                )
                let urlType = types.make(
                    .classType(ClassType(classSymbol: urlSymbol, args: [], nullability: .nonNull))
                )

                let candidates = symbols.lookupAll(
                    fqName: ["java", "net", "URL", "readText"].map(interner.intern)
                )

                let readTextSymbol = try #require(candidates.first { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == urlType
                        && signature.parameterTypes.isEmpty
                        && signature.returnType == types.stringType
                })
                #expect(
                    symbols.externalLinkName(for: readTextSymbol) == "kk_url_readText",
                    "URL.readText() should bind to runtime helper kk_url_readText"
                )

            }

        }
    }

}
