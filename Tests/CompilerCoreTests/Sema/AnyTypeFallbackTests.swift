#if canImport(Testing)
@testable import CompilerCore
import Testing

/// TYPE-111: Verify that premature `anyType` fallbacks in object literal,
/// callable reference, and compound assignment inference have been replaced
/// with `errorType` + diagnostics where appropriate.
@Suite
struct AnyTypeFallbackTests {

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
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

    @Test
    func testAnyTypeFallbacks() throws {
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
            // testCallableRefUnresolvedEmitsDiagnostic
            """
            package sample3

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

            // === testObjectLiteralPropertyWithInitializerInfersConcreteType ===
            do {
                let sample0Diagnostics = diagnosticsForPath(paths[0], in: ctx)
                guard let declID = firstUserObjectLiteralDeclIDInPath(in: ast, path: paths[0], sourceManager: ctx.sourceManager),
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
                let sample1Diagnostics = diagnosticsForPath(paths[1], in: ctx)
                guard let declID = firstUserObjectLiteralDeclIDInPath(in: ast, path: paths[1], sourceManager: ctx.sourceManager),
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
                let sample2Diagnostics = diagnosticsForPath(paths[2], in: ctx)
                let mainBody = try #require(findMainBodyStatementsInPath(in: ast, path: paths[2], sourceManager: ctx.sourceManager, interner: interner))
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
                #expect(!sample2Diagnostics.contains { $0.severity == .error }, "Unexpected diagnostics: \(sample2Diagnostics.map { "\($0.code): \($0.message)" })")
            }

            // === testCallableRefUnresolvedEmitsDiagnostic ===
            do {
                let sample3Diagnostics = diagnosticsForPath(paths[3], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: sample3Diagnostics)
            }
        }
    }
}

#endif
