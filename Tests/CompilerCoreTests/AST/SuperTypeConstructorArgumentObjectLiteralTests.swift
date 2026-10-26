#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SuperTypeConstructorArgumentObjectLiteralTests {
    @Test func objectSupertypeCommaStaysInsideInnerClassSuperArgument() throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface Callback { fun value(): String }
        open class Base(val callback: Callback)
        open class Outer(val x: String) {
            open inner class Inner
            inner class Nested : Base(object : Outer.Inner(), Callback {
                override fun value() = x
            })
            inner class Simple : Base(object : Callback { override fun value() = x })
            fun makeCallback(): Callback = object : Outer.Inner(), Callback {
                override fun value() = x
            }
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        guard let outer = ast.arena.decls.compactMap({ decl -> ClassDecl? in
            guard case let .classDecl(value) = decl,
                  ctx.interner.resolve(value.name) == "Outer"
            else { return nil }
            return value
        }).first else {
            Issue.record("Expected the Outer class.")
            return
        }
        guard let nested = outer.nestedClasses.compactMap({ declID -> ClassDecl? in
            guard case let .classDecl(value)? = ast.arena.decl(declID),
                  ctx.interner.resolve(value.name) == "Nested"
            else { return nil }
            return value
        }).first else {
            Issue.record("Expected the Nested inner class.")
            return
        }
        let nestedArgument = try #require(nested.superTypeEntries.first?.constructorArgs.first)
        guard case let .objectLiteral(superTypes, objectDeclID?, _) = ast.arena.expr(nestedArgument.expr),
              case let .objectDecl(objectDecl)? = ast.arena.decl(objectDeclID)
        else {
            Issue.record("Expected the complete anonymous object expression as the super constructor argument.")
            return
        }
        #expect(superTypes.count == 2)
        #expect(objectDecl.memberFunctions.count == 1)
        let memberID = try #require(objectDecl.memberFunctions.first)
        guard case let .funDecl(member)? = ast.arena.decl(memberID) else {
            Issue.record("Expected the anonymous object's override as a member function.")
            return
        }
        #expect(ctx.interner.resolve(member.name) == "value")
        #expect(member.modifiers.contains(.override))

        guard let simple = outer.nestedClasses.compactMap({ declID -> ClassDecl? in
            guard case let .classDecl(value)? = ast.arena.decl(declID),
                  ctx.interner.resolve(value.name) == "Simple"
            else { return nil }
            return value
        }).first else {
            Issue.record("Expected the Simple inner class.")
            return
        }
        #expect(simple.superTypeEntries.first?.constructorArgs.count == 1)

        guard let makeCallback = ast.arena.decls.compactMap({ decl -> FunDecl? in
            guard case let .funDecl(value) = decl,
                  ctx.interner.resolve(value.name) == "makeCallback"
            else { return nil }
            return value
        }).first else {
            Issue.record("Expected the makeCallback function.")
            return
        }
        guard case let .expr(bodyID, _) = makeCallback.body,
              case let .objectLiteral(memberSuperTypes, _, _) = ast.arena.expr(bodyID)
        else {
            Issue.record("Expected the ordinary member function's anonymous object expression.")
            return
        }
        #expect(memberSuperTypes.count == 2)
    }

    @Test func overrideRemainsInvalidOnATrueLocalFunction() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun invalid() {
            override fun local() = "bad"
        }
        """, includeStdlib: false)

        #expect(ast.arena.exprs.contains { expr in
            if case .localFunDecl = expr { return true }
            return false
        })
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0400"
                && $0.message == "modifier 'override' is not applicable to 'local function'."
        })
    }
}
#endif
