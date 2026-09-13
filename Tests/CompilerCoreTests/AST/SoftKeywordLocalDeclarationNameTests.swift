#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// `out` is a soft keyword: it means declaration-site variance inside a type
/// argument or type parameter list (`List<out T>`) and is an ordinary
/// identifier everywhere else, so `val out = 1` and `fun out() = 1` are valid
/// Kotlin.
///
/// The local-declaration builders identified the name slot with
/// `TypeRefParserCore.isTypeLikeNameToken`, which answers for a *type*
/// position and therefore reserves the variance keywords. Scanning for the
/// name token found nothing, `parseLocalDeclaration` returned nil, and the
/// statement fell back to expression parsing — leaving the `val` / `var`
/// keyword itself as an identifier reference and reporting
/// `KSWIFTK-SEMA-0013: Unresolved local variable 'val'`. Member properties,
/// top-level properties and value parameters were unaffected: they never go
/// through this scan.
///
/// See `Scripts/diff_cases/soft_keyword_local_names.kt` for the kotlinc
/// behaviour comparison.
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
    private func localDeclNames(_ ast: ASTModule, _ ctx: CompilationContext) -> [String] {
        ast.arena.exprs.compactMap { expr in
            guard case let .localDecl(name, _, _, _, _, _) = expr else { return nil }
            return ctx.interner.resolve(name)
        }
    }

    private func localFunDeclNames(_ ast: ASTModule, _ ctx: CompilationContext) -> [String] {
        ast.arena.exprs.compactMap { expr in
            guard case let .localFunDecl(name, _, _, _, _, _) = expr else { return nil }
            return ctx.interner.resolve(name)
        }
    }

    /// The bug's signature: the name scan found nothing, the declaration parse
    /// bailed out, and the statement was re-parsed as an expression — which
    /// turns the `val` / `var` keyword itself into a name reference.
    private func nameRefs(_ ast: ASTModule, _ ctx: CompilationContext) -> [String] {
        ast.arena.exprs.compactMap { expr in
            guard case let .nameRef(name, _) = expr else { return nil }
            return ctx.interner.resolve(name)
        }
    }

    // MARK: - the predicate

    /// A declaration *name* position accepts `out`; a type position must not,
    /// or `List<out T>` would parse its variance modifier as a type name.
    @Test
    func declarationNameTokenAcceptsOutWhileTypePositionStillReservesIt() {
        #expect(TypeRefParserCore.isDeclarationNameToken(.softKeyword(.out)))
        #expect(!TypeRefParserCore.isTypeLikeNameToken(.softKeyword(.out)))
    }

    /// `in` stays reserved in both positions: it is a hard keyword, so naming
    /// something `in` requires backticks, which reach the builders as
    /// `.backtickedIdentifier`.
    @Test
    func declarationNameTokenStillReservesIn() {
        #expect(!TypeRefParserCore.isDeclarationNameToken(.keyword(.in)))
        #expect(!TypeRefParserCore.isTypeLikeNameToken(.keyword(.in)))
    }

    // MARK: - local declarations

    @Test
    func localValNamedOutIsDeclared() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            val out = 1
            return out
        }
        """)
        #expect(localDeclNames(ast, ctx) == ["out"], "got \(localDeclNames(ast, ctx))")
        #expect(
            !nameRefs(ast, ctx).contains("val"),
            "the val keyword must not survive as a name reference; refs: \(nameRefs(ast, ctx))"
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
        let decls = ast.arena.exprs.compactMap { expr -> (String, Bool)? in
            guard case let .localDecl(name, isMutable, _, _, _, _) = expr else { return nil }
            return (ctx.interner.resolve(name), isMutable)
        }
        #expect(decls.map(\.0) == ["out"], "got \(decls)")
        #expect(decls.first?.1 == true, "var must stay mutable")
        #expect(
            !nameRefs(ast, ctx).contains("var"),
            "the var keyword must not survive as a name reference; refs: \(nameRefs(ast, ctx))"
        )
    }

    /// The local-function name slot used the same predicate, so the scan skipped
    /// `out` and took the *return type* token as the function's name.
    @Test
    func localFunctionNamedOutIsDeclared() throws {
        let (ast, ctx) = try buildAST(from: """
        fun f(): Int {
            fun out(): Int = 7
            return out()
        }
        """)
        #expect(
            localFunDeclNames(ast, ctx) == ["out"],
            "the local function must be named out, not its return type; got \(localFunDeclNames(ast, ctx))"
        )
    }

    /// Declarations inside a block expression reach a third copy of the same
    /// name scan.
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
        #expect(
            localDeclNames(ast, ctx).sorted() == ["out", "result"],
            "got \(localDeclNames(ast, ctx))"
        )
        #expect(
            !nameRefs(ast, ctx).contains("val"),
            "refs: \(nameRefs(ast, ctx))"
        )
    }

    // MARK: - setter parameter name

    /// `set(out) { ... }` names the setter's value parameter, another name slot
    /// that used the type-position predicate. The scan skipped `out`, the
    /// accessor got no parameter name, and the body's reference to it went
    /// unresolved.
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
        }.first { ctx.interner.resolve($0.name) == "x" }
        let propertyDecl = try #require(property)
        let setter = try #require(propertyDecl.setter)
        let parameterName = try #require(setter.parameterName, "the setter lost its parameter name")
        #expect(ctx.interner.resolve(parameterName) == "out")
    }

    /// The object-literal member parser keeps its own copy of the setter-name
    /// scan. Only the AST is asserted here: an object-literal property with a
    /// custom setter does not survive lowering yet, for reasons unrelated to
    /// the parameter's name (it fails the same way with `set(value)`).
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
        }.map { ctx.interner.resolve($0) }
        #expect(names == ["out"], "got \(names)")
    }

    // MARK: - variance is unaffected

    /// The widened predicate is only consulted for name slots, so `out` in a
    /// type parameter list still parses as covariance.
    @Test
    func typeParameterVarianceStillParses() throws {
        let (ast, ctx) = try buildAST(from: """
        class Box<out T>(val v: T)
        """)
        let box = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case let .classDecl(classDecl) = decl else { return nil }
            return classDecl
        }.first { ctx.interner.resolve($0.name) == "Box" }
        let classDecl = try #require(box)
        let typeParam = try #require(classDecl.typeParams.first)
        #expect(
            ctx.interner.resolve(typeParam.name) == "T",
            "the type parameter name must be T, not the variance keyword"
        )
        #expect(typeParam.variance == .out, "variance must still be covariant")
    }
}
#endif
