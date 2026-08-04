#if canImport(Testing)
@testable import CompilerCore
import Testing

/// TYPE-111: Verify that premature `anyType` fallbacks in object literal,
/// callable reference, and compound assignment inference have been replaced
/// with `errorType` + diagnostics where appropriate.
@Suite
struct AnyTypeFallbackTests {

    // MARK: - Object Literal

    // MARK: - Callable Reference

    // MARK: - Helpers

    private func firstUserObjectLiteralDeclID(
        in ast: ASTModule,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID
            else {
                continue
            }
            guard let range = ast.arena.exprRange(exprID),
                  !sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
            else {
                continue
            }
            return declID
        }
        return nil
    }

    private func findMainBodyStatements(
        in ast: ASTModule,
        interner: StringInterner
    ) -> [ExprID]? {
        for file in ast.files {
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
            // testObjectLiteralPropertyWithInitializerInfersConcreteType
            """
            package sample0

                    fun main() {
                        val obj = object {
                            val x = 42
                        }
                        println(obj.x)
                    }

            """,
            // testObjectLiteralPropertyWithTypeAnnotationUsesAnnotatedType
            """
            package sample1

                    fun main() {
                        val obj = object {
                            val y: String = "hello"
                        }
                        println(obj.y)
                    }

            """,
            // testCallableRefResolvedNoDiagnostic
            """
            package sample2

                    fun greet(name: String): String = "Hello"
                    fun main() {
                        val ref = ::greet
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testObjectLiteralPropertyWithInitializerInfersConcreteType ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                // Find the object decl's property symbol and verify its type is Int, not Any.
                guard let declID = firstUserObjectLiteralDeclIDInPath(in: ast, path: sample0Path, sourceManager: ctx.sourceManager),
                      let decl = ast.arena.decl(declID),
                      case let .objectDecl(objectDecl) = decl,
                      let propertyDeclID = objectDecl.memberProperties.first,
                      let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
                else {
                    Issue.record("Expected object literal with property.")
                    return
                }
                let propertyType = sema.symbols.propertyType(for: propertySymbol)
                #expect(propertyType != nil)
                #expect(propertyType != sema.types.anyType,
                    "Object literal property with initializer should not fall back to Any.")
                #expect(propertyType == sema.types.intType)
                assertNoDiagnostic("KSWIFTK-SEMA-0101", in: sample0Diagnostics)

            }

            // === testObjectLiteralPropertyWithTypeAnnotationUsesAnnotatedType ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                guard let declID = firstUserObjectLiteralDeclIDInPath(in: ast, path: sample1Path, sourceManager: ctx.sourceManager),
                      let decl = ast.arena.decl(declID),
                      case let .objectDecl(objectDecl) = decl,
                      let propertyDeclID = objectDecl.memberProperties.first,
                      let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
                else {
                    Issue.record("Expected object literal with property.")
                    return
                }
                let propertyType = sema.symbols.propertyType(for: propertySymbol)
                #expect(propertyType == sema.types.stringType,
                    "Object literal property with type annotation should use annotated type.")
                assertNoDiagnostic("KSWIFTK-SEMA-0101", in: sample1Diagnostics)

            }

            // === testCallableRefResolvedNoDiagnostic ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                // Find the callable ref expression and verify its type is not Any or error.
                let mainBody = try #require(findMainBodyStatementsInPath(in: ast, path: sample2Path, sourceManager: ctx.sourceManager, interner: interner))
                for exprID in mainBody {
                    guard let expr = ast.arena.expr(exprID),
                          case let .localDecl(_, _, _, initializer, _, _) = expr,
                          let initializer,
                          let boundType = sema.bindings.exprType(for: initializer)
                    else { continue }
                    #expect(boundType != sema.types.anyType,
                        "Resolved callable reference should not be Any.")
                    #expect(boundType != sema.types.errorType,
                        "Resolved callable reference should not be errorType.")
                }

            }

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnostics() throws {

        let sources: [String] = [
            // testCallableRefUnresolvedEmitsDiagnostic
            """
            package sample0

                    fun main() {
                        val ref = ::nonExistentFunction
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCallableRefUnresolvedEmitsDiagnostic ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample0Diagnostics)

            }

        }
    }

}

#endif
