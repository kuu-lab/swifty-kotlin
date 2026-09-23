#if canImport(Testing)
import CompilerCore
import Testing

@Suite
struct LocalNamedNominalTypingTests {

    private func renderDiagnostics(_ ctx: CompilationContext) -> String {
        ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
    }

    private func memberFunction(
        named name: String,
        ofClass className: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .classDecl(classDecl) = decl,
                      interner.resolve(classDecl.name) == className
                else {
                    continue
                }
                for memberDeclID in classDecl.memberFunctions {
                    guard let memberDecl = ast.arena.decl(memberDeclID),
                          case let .funDecl(function) = memberDecl,
                          interner.resolve(function.name) == name
                    else {
                        continue
                    }
                    return function
                }
            }
        }
        return nil
    }

    private func localNominalDeclExpr(
        in statements: [ExprID],
        ast: ASTModule
    ) -> (exprID: ExprID, declID: DeclID)? {
        for exprID in statements {
            guard let expr = ast.arena.expr(exprID) else {
                continue
            }
            if case let .localNominalDecl(declID, _) = expr {
                return (exprID, declID)
            }
        }
        return nil
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

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {
        let sources: [String] = [
            // KUU-555: named local class in a function body must be registered
            // as a statement so `Local(...)` and `l.v` resolve.
            """
            package localnom0

            fun useLocalClass() {
                class Local(val v: Int)
                val l = Local(5)
                println(l.v)
            }
            """,
            // KUU-555: named local object in a function body must resolve as a
            // singleton (`Local.v`), not as an expression.
            """
            package localnom1

            fun useLocalObject() {
                object Local {
                    val v = 5
                }
                println(Local.v)
            }
            """,
            // KUU-555: named local object inside a class member function body.
            """
            package localnom2

            class Outer {
                fun probe(): Int {
                    object Local {
                        val v = 9
                    }
                    return Local.v
                }
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === local class ===
            do {
                let diagnostics = diagnosticsForPath(paths[0], in: ctx)
                let mainDecl = try #require(topLevelFunction(named: "useLocalClass", in: ast, interner: interner))
                guard case let .block(statements, _) = mainDecl.body else {
                    Issue.record("Expected block body for useLocalClass.")
                    return
                }

                let (localNominalExprID, classDeclID) = try #require(
                    localNominalDeclExpr(in: statements, ast: ast),
                    "Expected a localNominalDecl statement for `class Local`."
                )
                guard let decl = ast.arena.decl(classDeclID),
                      case let .classDecl(classDecl) = decl
                else {
                    Issue.record("Expected localNominalDecl to reference a classDecl.")
                    return
                }

                let classSymbol = try #require(sema.bindings.declSymbol(for: classDeclID))
                #expect(sema.symbols.symbol(classSymbol)?.kind == .class)

                let propertyDeclID = try #require(classDecl.memberProperties.first)
                let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
                #expect(propertySymbol != nil)

                // A class declaration statement yields Unit; only named
                // `object` statements bind the nominal instance type.
                let classStmtType = try #require(sema.bindings.exprType(for: localNominalExprID))
                #expect(classStmtType == sema.types.unitType)

                let memberExprID = try #require(
                    findMemberCall(named: "v", in: statements, ast: ast, interner: interner)
                )
                let memberSymbol = sema.bindings.identifierSymbol(for: memberExprID)
                #expect(memberSymbol == propertySymbol,
                        "`l.v` should resolve to the local class property. Diagnostics: \(renderDiagnostics(ctx))")

                #expect(!diagnostics.contains { $0.severity == .error },
                        "Unexpected diagnostics: \(renderDiagnostics(ctx))")
            }

            // === local object (top-level function) ===
            do {
                let diagnostics = diagnosticsForPath(paths[1], in: ctx)
                let mainDecl = try #require(topLevelFunction(named: "useLocalObject", in: ast, interner: interner))
                guard case let .block(statements, _) = mainDecl.body else {
                    Issue.record("Expected block body for useLocalObject.")
                    return
                }

                let (localNominalExprID, objectDeclID) = try #require(
                    localNominalDeclExpr(in: statements, ast: ast),
                    "Expected a localNominalDecl statement for `object Local`."
                )
                guard let decl = ast.arena.decl(objectDeclID),
                      case let .objectDecl(objectDecl) = decl
                else {
                    Issue.record("Expected localNominalDecl to reference an objectDecl.")
                    return
                }

                let objectSymbol = try #require(sema.bindings.declSymbol(for: objectDeclID))
                #expect(sema.symbols.symbol(objectSymbol)?.kind == .object)

                let objectType = try #require(sema.bindings.exprType(for: localNominalExprID))
                guard case .classType = sema.types.kind(of: objectType) else {
                    Issue.record("Expected localNominalDecl to bind the object instance type.")
                    return
                }

                let propertyDeclID = try #require(objectDecl.memberProperties.first)
                let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
                #expect(propertySymbol != nil)

                let memberExprID = try #require(
                    findMemberCall(named: "v", in: statements, ast: ast, interner: interner)
                )
                let receiverExprID = try #require(memberCallReceiver(for: memberExprID, ast: ast))
                let receiverType = try #require(
                    sema.bindings.exprType(for: receiverExprID),
                    "Receiver type should be inferred. Diagnostics: \(renderDiagnostics(ctx))"
                )
                #expect(receiverType == objectType)
                #expect(sema.bindings.identifierSymbol(for: memberExprID) == propertySymbol,
                        "`Local.v` should resolve to the object property. Diagnostics: \(renderDiagnostics(ctx))")

                #expect(!diagnostics.contains { $0.severity == .error },
                        "Unexpected diagnostics: \(renderDiagnostics(ctx))")
            }

            // === local object inside a class member function ===
            do {
                let diagnostics = diagnosticsForPath(paths[2], in: ctx)
                let probeDecl = try #require(
                    memberFunction(named: "probe", ofClass: "Outer", in: ast, interner: interner),
                    "Expected member function probe."
                )
                guard case let .block(statements, _) = probeDecl.body else {
                    Issue.record("Expected block body for probe.")
                    return
                }

                let (_, objectDeclID) = try #require(
                    localNominalDeclExpr(in: statements, ast: ast),
                    "Expected a localNominalDecl statement inside a member function."
                )
                let objectSymbol = try #require(sema.bindings.declSymbol(for: objectDeclID))
                #expect(sema.symbols.symbol(objectSymbol)?.kind == .object)

                #expect(!diagnostics.contains { $0.severity == .error },
                        "Unexpected diagnostics: \(renderDiagnostics(ctx))")
            }
        }
    }
}

#endif
