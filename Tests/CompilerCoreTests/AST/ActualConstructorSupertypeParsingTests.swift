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

    @Test
    func testMultilineAnnotatedPrimaryConstructorRetainsParametersAndBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class ArrayBox
        @CtorMarker(message = "constructor", nested = ReplaceWith("ArrayBox(size)"))
        @SecondMarker
        public constructor(size: Int) {
            private val storage = size
            val count: Int get() = storage
            operator fun get(index: Int): Int = storage + index
        }
        class GenericBox<T>
        @CtorMarker
        internal constructor(val item: T) : Holder<T> {
            fun read(): T = item
        }
        """, includeStdlib: false)

        try #require(!ctx.diagnostics.hasError, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")
        let box = try userClassDecl(named: "ArrayBox", in: ast, ctx: ctx)
        #expect(box.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["size"])
        #expect(box.primaryConstructorModifiers.contains(.public))
        #expect(box.primaryConstructorAnnotations.map(\.name) == ["CtorMarker", "SecondMarker"])
        #expect(box.annotations.isEmpty)
        let boxProperties = try memberProperties(of: box, in: ast)
        #expect(boxProperties.map { ctx.interner.resolve($0.name) } == ["storage", "count"])
        let boxFunctions = try memberFunctions(of: box, in: ast)
        #expect(boxFunctions.map { ctx.interner.resolve($0.name) } == ["get"])
        #expect(boxFunctions.first?.modifiers.contains(.operator) == true)
        #expect(box.hasPrimaryConstructorSyntax)

        let generic = try userClassDecl(named: "GenericBox", in: ast, ctx: ctx)
        #expect(generic.typeParams.count == 1)
        #expect(generic.primaryConstructorModifiers.contains(.internal))
        #expect(generic.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["item"])
        let genericProperties = try memberProperties(of: generic, in: ast)
        #expect(genericProperties.map { ctx.interner.resolve($0.name) } == ["item"])
        let genericFunctions = try memberFunctions(of: generic, in: ast)
        #expect(genericFunctions.map { ctx.interner.resolve($0.name) } == ["read"])
        #expect(supertypeNames(of: generic, in: ast, ctx: ctx) == ["Holder"])
    }

    @Test
    func testFollowingAnnotatedDeclarationsRemainOutsideConstructorlessClass() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Empty
        @NextClass("constructor")
        class Following(val value: Int) { fun read(): Int = value }
        class AnotherEmpty
        @NextFunction
        fun unrelated(): Int = 1
        """, includeStdlib: false)

        try #require(!ctx.diagnostics.hasError, "Unexpected parser diagnostics: \(ctx.diagnostics.diagnostics)")
        let empty = try userClassDecl(named: "Empty", in: ast, ctx: ctx)
        #expect(empty.primaryConstructorParams.isEmpty)
        #expect(empty.primaryConstructorAnnotations.isEmpty)
        #expect(empty.memberFunctions.isEmpty)
        let following = try userClassDecl(named: "Following", in: ast, ctx: ctx)
        #expect(following.annotations.map(\.name) == ["NextClass"])
        #expect(following.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["value"])
        let followingFunctions = try memberFunctions(of: following, in: ast)
        #expect(followingFunctions.map { ctx.interner.resolve($0.name) } == ["read"])
        let another = try userClassDecl(named: "AnotherEmpty", in: ast, ctx: ctx)
        #expect(another.memberFunctions.isEmpty)
        let unrelated = try #require(ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(function) = decl,
                  ctx.interner.resolve(function.name) == "unrelated" else { return nil }
            return function
        }.first)
        #expect(unrelated.annotations.map(\.name) == ["NextFunction"])
    }

    private func memberProperties(of classDecl: ClassDecl, in ast: ASTModule) throws -> [PropertyDecl] {
        try classDecl.memberProperties.map { declID in
            let property: PropertyDecl? = if case let .propertyDecl(property) = ast.arena.decl(declID) {
                property
            } else {
                nil
            }
            return try #require(property)
        }
    }

    private func memberFunctions(of classDecl: ClassDecl, in ast: ASTModule) throws -> [FunDecl] {
        try classDecl.memberFunctions.map { declID in
            let function: FunDecl? = if case let .funDecl(function) = ast.arena.decl(declID) {
                function
            } else {
                nil
            }
            return try #require(function)
        }
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
