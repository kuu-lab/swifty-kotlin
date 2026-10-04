#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite("SuperTypeParsing")
struct SuperTypeParsingTests {

    private func buildAST(_ source: String) throws -> (ASTModule, CompilationContext) {
        try buildASTModule(from: source)
    }

    /// First user-source class with the given name; bundled stdlib
    /// declarations share the arena and must be skipped.
    private func userClassDecl(named name: String, in ast: ASTModule, ctx: CompilationContext) throws -> ClassDecl {
        try #require(ast.arena.declarations().lazy.compactMap { decl -> ClassDecl? in
            guard case let .classDecl(cls) = decl,
                  isUserSourceRange(cls.range, in: ctx)
            else { return nil }
            return cls
        }.first { ctx.interner.resolve($0.name) == name })
    }

    private func userInterfaceDecl(named name: String, in ast: ASTModule, ctx: CompilationContext) throws -> InterfaceDecl {
        try #require(ast.arena.declarations().lazy.compactMap { decl -> InterfaceDecl? in
            guard case let .interfaceDecl(iface) = decl,
                  isUserSourceRange(iface.range, in: ctx)
            else { return nil }
            return iface
        }.first { ctx.interner.resolve($0.name) == name })
    }

    @Test
    func testInterfaceFunctionTypeLiteralSupertype() throws {
        let (ast, ctx) = try buildAST("""
        interface KProperty0<V> : () -> V
        """)

        #expect(!ctx.diagnostics.hasError)

        let iface = try userInterfaceDecl(named: "KProperty0", in: ast, ctx: ctx)
        #expect(iface.superTypes.count == 1)

        let superType = try #require(ast.arena.typeRef(iface.superTypes[0]))
        guard case .functionType(let contextReceivers, let receiver, let params, let returnType, let isSuspend, let nullable) = superType else {
            Issue.record("Expected function type supertype, got \(superType)")
            return
        }

        #expect(contextReceivers.isEmpty)
        #expect(receiver == nil)
        #expect(params.isEmpty)
        #expect(!isSuspend)
        #expect(!nullable)

        let returnRef = try #require(ast.arena.typeRef(returnType))
        guard case .named(let path, let args, let returnNullable) = returnRef else {
            Issue.record("Expected named return type, got \(returnRef)")
            return
        }
        #expect(path.map { ctx.interner.resolve($0) } == ["V"])
        #expect(args.isEmpty)
        #expect(!returnNullable)
    }

    @Test
    func testClassFunctionTypeLiteralSupertype() throws {
        let (ast, ctx) = try buildAST("""
        class KProperty0<V> : () -> V
        """)

        #expect(!ctx.diagnostics.hasError)

        let cls = try userClassDecl(named: "KProperty0", in: ast, ctx: ctx)
        #expect(cls.superTypeEntries.count == 1)

        let superType = try #require(ast.arena.typeRef(cls.superTypeEntries[0].typeRef))
        guard case .functionType(_, _, let params, let returnType, let isSuspend, let nullable) = superType else {
            Issue.record("Expected function type supertype, got \(superType)")
            return
        }
        #expect(params.isEmpty)
        #expect(!isSuspend)
        #expect(!nullable)

        let returnRef = try #require(ast.arena.typeRef(returnType))
        guard case .named(let path, let args, _) = returnRef else {
            Issue.record("Expected named return type, got \(returnRef)")
            return
        }
        #expect(path.map { ctx.interner.resolve($0) } == ["V"])
        #expect(args.isEmpty)
    }

    @Test
    func testNamedSupertypeWithConstructorInvocation() throws {
        let (ast, ctx) = try buildAST("""
        open class Parent(x: Int)
        class Child : Parent(42)
        """)

        #expect(!ctx.diagnostics.hasError)

        let child = try userClassDecl(named: "Child", in: ast, ctx: ctx)
        #expect(child.superTypeEntries.count == 1)

        let superType = try #require(ast.arena.typeRef(child.superTypeEntries[0].typeRef))
        guard case .named(let path, let args, let nullable) = superType else {
            Issue.record("Expected named supertype, got \(superType)")
            return
        }
        #expect(path.map { ctx.interner.resolve($0) } == ["Parent"])
        #expect(args.isEmpty)
        #expect(!nullable)
    }

    @Test
    func testReceiverFunctionTypeSupertype() throws {
        let (ast, ctx) = try buildAST("""
        interface Foo : String.() -> Unit
        """)

        #expect(!ctx.diagnostics.hasError)

        let iface = try userInterfaceDecl(named: "Foo", in: ast, ctx: ctx)
        #expect(iface.superTypes.count == 1)

        let superType = try #require(ast.arena.typeRef(iface.superTypes[0]))
        guard case .functionType(_, let receiver, let params, let returnType, _, _) = superType else {
            Issue.record("Expected function type supertype, got \(superType)")
            return
        }
        #expect(params.isEmpty)

        let receiverRef = try #require(receiver)
        let receiverType = try #require(ast.arena.typeRef(receiverRef))
        guard case .named(let path, let args, _) = receiverType else {
            Issue.record("Expected named receiver type, got \(receiverType)")
            return
        }
        #expect(path.map { ctx.interner.resolve($0) } == ["String"])
        #expect(args.isEmpty)

        let returnRef = try #require(ast.arena.typeRef(returnType))
        guard case .named(let returnPath, _, _) = returnRef else {
            Issue.record("Expected named return type, got \(returnRef)")
            return
        }
        #expect(returnPath.map { ctx.interner.resolve($0) } == ["Unit"])
    }
}
#endif
