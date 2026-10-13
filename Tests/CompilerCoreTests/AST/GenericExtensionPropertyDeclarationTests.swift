@testable import CompilerCore
import Testing

@Suite
struct GenericExtensionPropertyDeclarationTests {
    @Test(arguments: ["val <T> Box<T>.read: () -> T get() = { value }", "val <T : Any> Box<T>.read: () -> T get() = { value }", "val <T> Box<T>.read: () -> T where T : Any get() = { value }"])
    func genericPropertyHeadPreservesParametersAndGetter(_ declaration: String) throws {
        let (ast, ctx) = try buildASTModule(from: "class Box<T>(val value: T)\n" + declaration, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(ctx.interner.resolve(property.name) == "read")
        #expect(property.typeParams.count == 1)
        #expect(ctx.interner.resolve(property.typeParams[0].name) == "T")
        #expect(property.typeParams[0].upperBounds.count == (declaration.contains("Any") ? 1 : 0))
        #expect(property.receiverType != nil)
        #expect(property.initializer == nil)
        guard let typeRef = property.type.flatMap({ ast.arena.typeRef($0) }),
              case .functionType = typeRef, let getter = property.getter,
              case let .expr(expression, _) = getter.body,
              case .lambdaLiteral = ast.arena.expr(expression) else {
            Issue.record("Generic declaration must retain its function type and lambda getter")
            return
        }
    }

    @Test(arguments: ["where", "p.where"])
    func softKeywordWhereRemainsAPropertyType(_ type: String) throws {
        let (ast, ctx) = try buildASTModule(from: "package p\nclass where\nval value: \(type) = where()", includeStdlib: false)
        #expect(!ctx.diagnostics.hasError)
        let property = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(property.type != nil)
    }

    @Test(arguments: ["val <reified T> T.kind: (Any) -> Boolean inline get() = { it is T }", "val <reified T> T.kind: (Any) -> Boolean\n    inline get() = { it is T }"])
    func accessorInlineIsPreserved(_ declaration: String) throws {
        let (ast, ctx) = try buildASTModule(from: declaration, includeStdlib: false)
        #expect(!ctx.diagnostics.hasError)
        let property = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(property.getter?.isInline == true)
        #expect(property.allAccessorsAreInline)
        #expect(property.type != nil)
        #expect(property.initializer == nil)
    }

    @Test(arguments: ["inline", "p.inline", "() -> inline"])
    func softKeywordInlineRemainsAPropertyType(_ type: String) throws {
        let (ast, ctx) = try buildASTModule(from: "package p\nclass inline\nval value: \(type) get() = TODO()", includeStdlib: false)
        #expect(!ctx.diagnostics.hasError)
        let property = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(property.type != nil)
        #expect(property.getter?.isInline != true)
    }

    @Test(arguments: ["Any inline", "Any @A", "@A Any @A", "@A @A Any @A"])
    func whereBoundsKeepTypeAnnotationsAndExcludeAccessorModifiers(_ bound: String) throws {
        let (ast, ctx) = try buildASTModule(
            from: "annotation class A\nclass Box<T>(val value: T)\nval <T> Box<T>.read: T where T : \(bound) get() = value",
            includeStdlib: false
        )
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let property = try #require(ast.files.flatMap(\.topLevelDecls).compactMap { id -> PropertyDecl? in
            guard case let .propertyDecl(value) = ast.arena.decl(id) else { return nil }
            return value
        }.first)
        #expect(property.typeParams.first?.upperBounds.count == 1)
        #expect(property.getter != nil)
    }
}
