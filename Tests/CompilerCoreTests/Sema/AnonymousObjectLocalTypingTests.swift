#if canImport(Testing)
import CompilerCore
import Testing

@Suite
struct AnonymousObjectLocalTypingTests {

    private func topLevelFunction(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl
                else {
                    continue
                }
                if interner.resolve(function.name) == name {
                    return function
                }
            }
        }
        return nil
    }

    private func findMemberCall(
        named name: String,
        in exprIDs: [ExprID],
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        for exprID in exprIDs {
            if let match = findMemberCall(named: name, exprID: exprID, ast: ast, interner: interner) {
                return match
            }
        }
        return nil
    }

    private func findMemberCall(
        named name: String,
        exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .memberCall(receiver, callee, _, args, _):
            if args.isEmpty, interner.resolve(callee) == name {
                return exprID
            }
            if let nested = findMemberCall(named: name, exprID: receiver, ast: ast, interner: interner) {
                return nested
            }
            for arg in args {
                if let nested = findMemberCall(named: name, exprID: arg.expr, ast: ast, interner: interner) {
                    return nested
                }
            }
            return nil
        case let .call(callee, _, args, _):
            if let nested = findMemberCall(named: name, exprID: callee, ast: ast, interner: interner) {
                return nested
            }
            for arg in args {
                if let nested = findMemberCall(named: name, exprID: arg.expr, ast: ast, interner: interner) {
                    return nested
                }
            }
            return nil
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                if let nested = findMemberCall(named: name, exprID: statement, ast: ast, interner: interner) {
                    return nested
                }
            }
            if let trailingExpr,
               let nested = findMemberCall(named: name, exprID: trailingExpr, ast: ast, interner: interner)
            {
                return nested
            }
            return nil
        default:
            return nil
        }
    }

    private func memberCallReceiver(
        for exprID: ExprID,
        ast: ASTModule
    ) -> ExprID? {
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(receiver, _, _, _, _) = expr
        else {
            return nil
        }
        return receiver
    }

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

    private func renderDiagnostics(_ ctx: CompilationContext) -> String {
        ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
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
            // testAnonymousObjectBodyProducesLocalNominalTypeAndResolvableProperty
            """
            package sample0

                    fun main() {
                        val local = object {
                            val value = 7
                        }
                        println(local.value)
                    }

            """,
            // testAnonymousObjectCanImplementMultipleInterfacesWithoutClassInheritanceDiagnostic
            """
            package sample1

                    interface First
                    interface Second
                    fun main() {
                        val local = object : First, Second {
                            val marker = 1
                        }
                        println(local)
                    }

            """,
            // testAnonymousObjectCallablePropertyCanBeInvokedFromMemberFunction
            """
            package sample2

                    interface Runner {
                        fun run(value: Int): Int
                    }

                    fun main() {
                        val local = object : Runner {
                            val callback: (Int) -> Int = { value -> value + 1 }
                            override fun run(value: Int): Int = this.callback(value)
                        }
                        println(local.run(41))
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testAnonymousObjectBodyProducesLocalNominalTypeAndResolvableProperty ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let mainDecl = try #require(topLevelFunction(named: "main", in: ast, interner: interner))
                guard case let .block(statements, _) = mainDecl.body else {
                    Issue.record("Expected block body for main.")
                    return
                }

                let localDeclExprID = try #require(statements.first)
                guard let localDeclExpr = ast.arena.expr(localDeclExprID),
                      case let .localDecl(_, _, _, initializer, _, _) = localDeclExpr,
                      let initializer
                else {
                    Issue.record("Expected local declaration with object literal initializer.")
                    return
                }

                guard let objectExpr = ast.arena.expr(initializer),
                      case let .objectLiteral(_, declID, _) = objectExpr,
                      let declID,
                      let decl = ast.arena.decl(declID),
                      case let .objectDecl(objectDecl) = decl
                else {
                    Issue.record("Expected object literal to retain a synthetic object declaration.")
                    return
                }

                #expect(objectDecl.memberProperties.count == 1)
                let objectSymbol = try #require(sema.bindings.declSymbol(for: declID))
                #expect(sema.symbols.symbol(objectSymbol) != nil)

                let propertyDeclID = try #require(objectDecl.memberProperties.first)
                let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
                #expect(
                    propertySymbol != nil,
                    "Anonymous object property should be bound. Diagnostics: \(renderDiagnostics(ctx))"
                )

                let objectType = try #require(sema.bindings.exprType(for: initializer))
                guard case .classType = sema.types.kind(of: objectType) else {
                    Issue.record("Expected anonymous object initializer to infer a nominal class type.")
                    return
                }

                let memberExprID = try #require(
                    findMemberCall(named: "value", in: statements, ast: ast, interner: interner)
                )
                let receiverExprID = try #require(memberCallReceiver(for: memberExprID, ast: ast))
                let receiverType = try #require(
                    sema.bindings.exprType(for: receiverExprID),
                    "Receiver type should be inferred. Diagnostics: \(renderDiagnostics(ctx))"
                )
                #expect(receiverType == objectType)

                let memberSymbol = sema.bindings.identifierSymbol(for: memberExprID)
                #expect(
                    memberSymbol != nil,
                    "Member access should resolve to the anonymous object property. Diagnostics: \(renderDiagnostics(ctx))"
                )
                #expect(!sample0Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(renderDiagnostics(ctx))")

            }

            // === testAnonymousObjectCanImplementMultipleInterfacesWithoutClassInheritanceDiagnostic ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                guard let declID = firstUserObjectLiteralDeclIDInPath(in: ast, path: sample1Path, sourceManager: ctx.sourceManager)
                else {
                    Issue.record("Expected object literal declaration.")
                    return
                }

                let objectSymbol = try #require(sema.bindings.declSymbol(for: declID))
                let directSupertypes = sema.symbols.directSupertypes(for: objectSymbol)
                let supertypeNames = Set(
                    directSupertypes.compactMap { symbolID in
                        sema.symbols.symbol(symbolID)?.fqName.last.map(interner.resolve)
                    }
                )

                #expect(supertypeNames == ["First", "Second"])
                assertNoDiagnostic("KSWIFTK-SEMA-0170", in: sample1Diagnostics)
                #expect(!sample1Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(renderDiagnostics(ctx))")

            }

            // === testAnonymousObjectCallablePropertyCanBeInvokedFromMemberFunction ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(!sample2Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(renderDiagnostics(ctx))")

            }

        }
    }

}

#endif
