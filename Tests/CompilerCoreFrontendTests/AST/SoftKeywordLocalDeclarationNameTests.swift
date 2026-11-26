#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SoftKeywordLocalDeclarationNameTests {
    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        try runFrontend(ctx)
        return (try #require(ctx.ast), ctx)
    }

    /// Names of `Expr.localDecl` nodes in the module. `runFrontend` stops after
    /// `BuildASTPhase`, which is the phase that contains the defect, so the
    /// assertions below read the AST directly rather than waiting for a Sema
    /// diagnostic. `includeStdlib: false` keeps the arena to the test source,
    /// so an arena-wide scan cannot collide with a stdlib declaration.
    private func localDeclNames(_ ast: ASTModule) -> [InternedString] {
        ast.arena.exprs.compactMap { expr in
            guard case let .localDecl(name, _, _, _, _, _, _) = expr else { return nil }
            return name
        }
    }

    private func localFunDeclNames(_ ast: ASTModule) -> [InternedString] {
        ast.arena.exprs.compactMap { expr in
            guard case let .localFunDecl(name, _, _, _, _, _, _, _, _) = expr else { return nil }
            return name
        }
    }

    private func nameRefs(_ ast: ASTModule) -> [InternedString] {
        ast.arena.exprs.compactMap { expr in
            guard case let .nameRef(name, _) = expr else { return nil }
            return name
        }
    }

    @Test
    func declarationNameTokenAcceptsOutWhileTypePositionStillReservesIt() {
        #expect(TypeRefParserCore.isDeclarationNameToken(.softKeyword(.out)))
        #expect(!TypeRefParserCore.isTypeLikeNameToken(.softKeyword(.out)))
    }

    @Test
    func declarationNameTokenStillReservesIn() {
        #expect(!TypeRefParserCore.isDeclarationNameToken(.keyword(.in)))
        #expect(!TypeRefParserCore.isTypeLikeNameToken(.keyword(.in)))
    }

    @Test
    func localValNamedOutIsDeclared() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            val out = 1
            return out
        }
        """)
        #expect(
            localDeclNames(ast) == [ctx.interner.intern(SoftKeyword.out.rawValue)],
            "got \(localDeclNames(ast).map(ctx.interner.resolve))"
        )
        #expect(
            !nameRefs(ast).contains(ctx.interner.intern(Keyword.val.rawValue)),
            "the val keyword must not survive as a name reference; refs: \(nameRefs(ast).map(ctx.interner.resolve))"
        )
    }

    @Test
    func localVarNamedOutIsDeclaredAndAssignable() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            var out = 1
            out = out + 1
            return out
        }
        """)
        let decls = ast.arena.exprs.compactMap { expr -> (InternedString, Bool)? in
            guard case let .localDecl(name, isMutable, _, _, _, _, _) = expr else { return nil }
            return (name, isMutable)
        }
        #expect(decls.map(\.0) == [ctx.interner.intern(SoftKeyword.out.rawValue)], "got \(decls)")
        #expect(decls.first?.1 == true, "var must stay mutable")
        #expect(
            !nameRefs(ast).contains(ctx.interner.intern(Keyword.var.rawValue)),
            "the var keyword must not survive as a name reference; refs: \(nameRefs(ast).map(ctx.interner.resolve))"
        )
    }

    @Test
    func localFunctionNamedOutIsDeclared() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            fun out(): Int = 7
            return out()
        }
        """)
        #expect(
            localFunDeclNames(ast) == [ctx.interner.intern(SoftKeyword.out.rawValue)],
            "the local function must be named out, not its return type; got \(localFunDeclNames(ast).map(ctx.interner.resolve))"
        )
    }

    @Test
    func localExtensionNamedOutPreservesReceiver() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            fun Int.out(): Int = this
            return 7.out()
        }
        """)
        let receivers = ast.arena.exprs.compactMap { expr -> TypeRefID? in
            guard case let .localFunDecl(_, receiver, _, _, _, _, _, _, _) = expr else { return nil }
            return receiver
        }
        #expect(localFunDeclNames(ast) == [ctx.interner.intern(SoftKeyword.out.rawValue)])
        #expect(receivers.count == 1)
    }

    @Test
    func blockExpressionLocalNamedOutIsDeclared() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(flag: Boolean): Int {
            val result = if (flag) {
                val out = 2
                out
            } else {
                0
            }
            return result
        }
        """)
        let names = localDeclNames(ast)
        #expect(names.count == 2)
        #expect(Set(names) == Set(["out", "result"].map(ctx.interner.intern)), "got \(names.map(ctx.interner.resolve))")
        #expect(
            !nameRefs(ast).contains(ctx.interner.intern(Keyword.val.rawValue)),
            "refs: \(nameRefs(ast).map(ctx.interner.resolve))"
        )
    }

    @Test
    func setterParameterNamedOutIsBound() throws {
        let (ast, ctx) = try buildAST(from: """
        class C {
            var x: Int = 0
                set(out) { field = out + 1 }
        }
        """)
        let property = ast.arena.declarations().compactMap { decl -> PropertyDecl? in
            guard case let .propertyDecl(propertyDecl) = decl else { return nil }
            return propertyDecl
        }.first { $0.name == ctx.interner.intern("x") }
        let propertyDecl = try #require(property)
        let setter = try #require(propertyDecl.setter)
        let parameterName = try #require(setter.parameterName, "the setter lost its parameter name")
        #expect(parameterName == ctx.interner.intern(SoftKeyword.out.rawValue))
    }

    @Test
    func objectLiteralSetterParameterNamedOutIsBound() throws {
        let (ast, ctx) = try buildAST(from: """
        interface Holder { var y: Int }

        fun make(): Holder = object : Holder {
            override var y: Int = 0
                set(out) { field = out + 2 }
        }
        """)
        let names = ast.arena.exprs.compactMap { expr -> InternedString? in
            guard case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  case let .objectDecl(objectDecl) = ast.arena.decl(declID)
            else {
                return nil
            }
            return objectDecl.memberProperties.compactMap { propertyID -> InternedString? in
                guard case let .propertyDecl(propertyDecl) = ast.arena.decl(propertyID) else { return nil }
                return propertyDecl.setter?.parameterName
            }.first
        }
        #expect(names == [ctx.interner.intern(SoftKeyword.out.rawValue)], "got \(names.map(ctx.interner.resolve))")
    }

    @Test
    func typeParameterVarianceStillParses() throws {
        let (ast, ctx) = try buildAST(from: """
        class Box<out T>(val v: T)
        """)
        let box = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case let .classDecl(classDecl) = decl else { return nil }
            return classDecl
        }.first { $0.name == ctx.interner.intern("Box") }
        let classDecl = try #require(box)
        let typeParam = try #require(classDecl.typeParams.first)
        #expect(
            typeParam.name == ctx.interner.intern("T"),
            "the type parameter name must be T, not the variance keyword"
        )
        #expect(typeParam.variance == .out, "variance must still be covariant")
    }
}
#endif
