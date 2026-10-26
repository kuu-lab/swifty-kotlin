#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ObjectLiteralNestedInnerClassTests {
    @Test(arguments: [false, true])
    func nestedInnerClassIsRetainedInEitherDeclarationOrder(_ innerClassFirst: Bool) throws {
        let members = innerClassFirst
            ? """
                inner class A(val ok: String)
                val a = A("OK")
                """
            : """
                val a = A("OK")
                inner class A(val ok: String)
                """
        let ctx = makeContextFromSource("""
        fun box(): String {
            return object {
                \(members)
            }.a.ok
        }
        """)
        try runToLowering(ctx)

        let errors = ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .map { "\($0.code): \($0.message)" }
        #expect(!ctx.diagnostics.hasError, "Got: \(errors)")
        let ast = try #require(ctx.ast)
        let objectDeclCandidates = ast.arena.exprs.compactMap { expr -> ObjectDecl? in
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  case let .objectDecl(decl)? = ast.arena.decl(declID),
                  decl.nestedClasses.count == 1
            else {
                return nil
            }
            return decl
        }
        let objectDecl = try #require(objectDeclCandidates.first)

        #expect(objectDecl.memberProperties.count == 1)
        let propertyID = try #require(objectDecl.memberProperties.first)
        guard case let .propertyDecl(property)? = ast.arena.decl(propertyID) else {
            Issue.record("Expected the anonymous object's `a` property.")
            return
        }
        #expect(property.initializer != nil)

        let nestedClassID = try #require(objectDecl.nestedClasses.first)
        guard case let .classDecl(nestedClass)? = ast.arena.decl(nestedClassID) else {
            Issue.record("Expected nested class `A`.")
            return
        }
        #expect(ctx.interner.resolve(nestedClass.name) == "A")
        #expect(nestedClass.isInner)
        #expect(nestedClass.memberProperties.count == 1)

        let okAccesses = ast.arena.exprs.enumerated().compactMap { rawID, expr -> (ExprID, SymbolID)? in
            guard case let .memberCall(_, callee, _, args, _) = expr,
                  ctx.interner.resolve(callee) == "ok",
                  args.isEmpty
            else {
                return nil
            }
            let exprID = ExprID(rawValue: Int32(rawID))
            let symbol = ctx.sema?.bindings.identifierSymbol(for: exprID)
                ?? ctx.sema?.bindings.callBinding(for: exprID)?.chosenCallee
            return symbol.map { (exprID, $0) }
        }
        #expect(okAccesses.count == 1)
        let nestedPropertyID = try #require(nestedClass.memberProperties.first)
        let nestedPropertySymbol = try #require(ctx.sema?.bindings.declSymbols[nestedPropertyID])
        #expect(okAccesses.first?.1 == nestedPropertySymbol)
    }
}
#endif
