#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ActualConstructorSupertypeParsingTests {
    @Test
    func testActualConstructorModifiersAndAnnotationsPreserveSupertypes() throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface IP
        open class Base(message: String)

        actual open class MessageCtor actual constructor(message: String): IP
        actual open class EmptyCtor actual constructor(): IP
        actual open class BaseArgument actual constructor(message: String): Base(message)
        actual open class GenericCtor<T> actual constructor(value: T): IP
        actual open class HiddenCtor @CtorMarker private actual constructor(message: String): IP
        actual open class HeaderCtor(message: String): IP
        actual open class NoSupertype actual constructor(message: String)
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")

        let messageCtor = try userClassDecl(named: "MessageCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: messageCtor, in: ast, ctx: ctx) == ["IP"])

        let emptyCtor = try userClassDecl(named: "EmptyCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: emptyCtor, in: ast, ctx: ctx) == ["IP"])

        let baseArgument = try userClassDecl(named: "BaseArgument", in: ast, ctx: ctx)
        #expect(supertypeNames(of: baseArgument, in: ast, ctx: ctx) == ["Base"])
        #expect(baseArgument.superTypeEntries.first?.constructorArgs.count == 1)

        let genericCtor = try userClassDecl(named: "GenericCtor", in: ast, ctx: ctx)
        #expect(genericCtor.typeParams.count == 1)
        #expect(supertypeNames(of: genericCtor, in: ast, ctx: ctx) == ["IP"])

        let hiddenCtor = try userClassDecl(named: "HiddenCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: hiddenCtor, in: ast, ctx: ctx) == ["IP"])
        #expect(hiddenCtor.primaryConstructorModifiers.contains(.private))
        #expect(hiddenCtor.primaryConstructorModifiers.contains(.actual))
        #expect(hiddenCtor.primaryConstructorAnnotations.map(\.name) == ["CtorMarker"])

        let headerCtor = try userClassDecl(named: "HeaderCtor", in: ast, ctx: ctx)
        #expect(supertypeNames(of: headerCtor, in: ast, ctx: ctx) == ["IP"])

        let noSupertype = try userClassDecl(named: "NoSupertype", in: ast, ctx: ctx)
        #expect(noSupertype.superTypeEntries.isEmpty)
    }

    private func userClassDecl(named name: String, in ast: ASTModule, ctx: CompilationContext) throws -> ClassDecl {
        try #require(ast.arena.declarations().lazy.compactMap { decl -> ClassDecl? in
            guard case let .classDecl(classDecl) = decl,
                  isUserSourceRange(classDecl.range, in: ctx)
            else { return nil }
            return classDecl
        }.first { ctx.interner.resolve($0.name) == name })
    }

    private func supertypeNames(of classDecl: ClassDecl, in ast: ASTModule, ctx: CompilationContext) -> [String] {
        classDecl.superTypeEntries.compactMap { entry in
            guard let typeRef = ast.arena.typeRef(entry.typeRef),
                  case let .named(path, _, _) = typeRef
            else { return nil }
            return path.map { ctx.interner.resolve($0) }.joined(separator: ".")
        }
    }
}
#endif
