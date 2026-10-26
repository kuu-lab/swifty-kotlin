#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimaryConstructorNewlineSupertypeTests {
    @Test(arguments: [
        "class ParseException(val value: Int) : Exception(\"parse\")",
        "class ParseException(val value: Int)\n    : Exception(\"parse\")",
        "class ParseException constructor(val value: Int)\n    : Exception(\"parse\")",
        "class ParseException(@Suppress(\"CanBeParameter\") public val value: Int)\n    : Exception(\"parse\")",
        "class ParseException(\n    @Suppress(\"CanBeParameter\")\n    public val value: Int,\n)\n    : Exception(\"parse\")",
    ])
    func exceptionHeaderPreservesConstructorAndSupertype(header: String) throws {
        let source = """
        \(header)
        class Following
        fun after() = 1
        """
        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let exception = try #require(firstClassDecl(named: "ParseException", in: ast, interner: ctx.interner))
        #expect(exception.primaryConstructorParams.map { ctx.interner.resolve($0.name) } == ["value"])
        #expect(exception.hasPrimaryConstructorSyntax)
        #expect(try supertypeNames(exception.superTypeEntries.map(\.typeRef), ast: ast, ctx: ctx) == ["Exception"])
        #expect(exception.superTypeEntries.first?.constructorArgs.count == 1)
        let following = try #require(firstClassDecl(named: "Following", in: ast, interner: ctx.interner))
        #expect(exception.range.end.offset <= following.range.start.offset)
        #expect(following.superTypeEntries.isEmpty)
        #expect(ast.arena.declarations().compactMap { decl -> String? in
            guard case let .funDecl(function) = decl else { return nil }
            return ctx.interner.resolve(function.name)
        } == ["after"])
    }

    @Test(arguments: ["()", "<T>(val value: T)", ""])
    func classHeaderRetainsMultipleSupertypesAndBody(constructor: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface First
        interface Second
        class Target\(constructor)
            : First,
              Second {
            fun member() = 1
        }
        fun after() = 2
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let target = try #require(firstClassDecl(named: "Target", in: ast, interner: ctx.interner))
        #expect(try supertypeNames(target.superTypeEntries.map(\.typeRef), ast: ast, ctx: ctx) == ["First", "Second"])
        #expect(target.memberFunctions.count == 1)
    }

    @Test
    func interfaceHeaderRetainsMultipleSupertypesAcrossNewlines() throws {
        let (ast, ctx) = try buildASTModule(from: """
        interface First
        interface Second
        interface Combined
            : First,
              Second
        class Following()
        fun after() = 1
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let combined = try #require(ast.arena.declarations().compactMap { decl -> InterfaceDecl? in
            guard case let .interfaceDecl(iface) = decl,
                  ctx.interner.resolve(iface.name) == "Combined" else { return nil }
            return iface
        }.first)
        #expect(try supertypeNames(combined.superTypes, ast: ast, ctx: ctx) == ["First", "Second"])
        _ = try #require(firstClassDecl(named: "Following", in: ast, interner: ctx.interner))
    }

    @Test(arguments: ["", "\n    : First", "\n    : First {}"])
    func constructorHeaderDoesNotAbsorbFollowingDeclarations(tail: String) {
        let parsed = parse("""
        class Target(val value: Int)\(tail)
        @Suppress("unused")
        class Following(val other: Int)
        fun after() = 1
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        let declarations = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(declarations.map(\.kind) == [.classDecl, .classDecl, .funDecl])
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        if declarations.count == 3 {
            #expect(declarations[0].range.end.offset <= declarations[1].range.start.offset)
            #expect(declarations[1].range.end.offset <= declarations[2].range.start.offset)
        }
    }

    @Test(arguments: ["println(7)", "val result = 7\nprintln(result)"])
    func implicitConstructorDoesNotAbsorbFollowingScriptStatements(statement: String) {
        let parsed = parse("class Target(val value: Int)\n\(statement)")
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .script)
        let declarations = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(declarations.first?.kind == .classDecl)
        #expect(declarations.first?.range.end.offset == "class Target(val value: Int)".utf8.count)
        #expect(declarations.count >= 2)
    }

    @Test(arguments: ["fun(): Int { return 7 }", "object {}"])
    func implicitConstructorRetainsDeclarationLikeDefaultExpressions(expression: String) throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Target(val value: Any =
            \(expression))
        fun after() = 1
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let target = try #require(firstClassDecl(named: "Target", in: ast, interner: ctx.interner))
        #expect(target.primaryConstructorParams.count == 1)
        #expect(target.primaryConstructorParams.first?.defaultValue != nil)
        _ = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
    }

    @Test
    func annotatedExceptionAcceptsThrowWithExtensionReceiver() throws {
        let ctx = try semaContext(for: ["""
        abstract class ErrorResult
        public class ParseException(@Suppress("CanBeParameter") public val errorResult: ErrorResult)
            : Exception("Could not parse input: $errorResult")
        fun ErrorResult.toParsedOrThrow(): Nothing = throw ParseException(this)
        """])
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors)")
    }

    private func supertypeNames(_ refs: [TypeRefID], ast: ASTModule, ctx: CompilationContext) throws -> [String] {
        try refs.map { ref in
            let type = try #require(ast.arena.typeRef(ref))
            guard case let .named(path, _, _) = type else {
                Issue.record("Expected named supertype, got \(type)")
                return ""
            }
            return path.map { ctx.interner.resolve($0) }.joined(separator: ".")
        }
    }
}
#endif
