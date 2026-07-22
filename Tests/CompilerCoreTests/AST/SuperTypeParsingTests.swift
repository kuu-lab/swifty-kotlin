#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite("SuperTypeParsing")
struct SuperTypeParsingTests {

    private func buildAST(_ source: String) throws -> (ASTModule, CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        let ast = try #require(ctx.ast)
        return (ast, ctx)
    }

    private func isUserDecl(_ decl: some Any, range: SourceRange, in ctx: CompilationContext) -> Bool {
        !ctx.sourceManager.path(of: range.start.file).hasPrefix("__bundled_")
    }

    @Test
    func testInterfaceFunctionTypeLiteralSupertype() throws {
        let (ast, ctx) = try buildAST("""
        interface KProperty0<V> : () -> V
        """)

        #expect(!ctx.diagnostics.hasError)

        let interfaces = ast.arena.declarations().compactMap { decl -> InterfaceDecl? in
            guard case .interfaceDecl(let iface) = decl,
                  isUserDecl(iface, range: iface.range, in: ctx)
            else { return nil }
            return iface
        }
        let iface = try #require(interfaces.first { ctx.interner.resolve($0.name) == "KProperty0" })
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

        let classes = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case .classDecl(let cls) = decl,
                  isUserDecl(cls, range: cls.range, in: ctx)
            else { return nil }
            return cls
        }
        let cls = try #require(classes.first { ctx.interner.resolve($0.name) == "KProperty0" })
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

        let classes = ast.arena.declarations().compactMap { decl -> ClassDecl? in
            guard case .classDecl(let cls) = decl,
                  isUserDecl(cls, range: cls.range, in: ctx)
            else { return nil }
            return cls
        }
        let child = try #require(classes.first { ctx.interner.resolve($0.name) == "Child" })
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

        let interfaces = ast.arena.declarations().compactMap { decl -> InterfaceDecl? in
            guard case .interfaceDecl(let iface) = decl,
                  isUserDecl(iface, range: iface.range, in: ctx)
            else { return nil }
            return iface
        }
        let iface = try #require(interfaces.first { ctx.interner.resolve($0.name) == "Foo" })
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
