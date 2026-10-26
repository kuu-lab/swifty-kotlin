#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ClassBodyNewlineTests {
    @Test(arguments: [
        "class Target(val value: Int) {",
        "class Target(val value: Int)\n{",
        "class Target constructor(val value: Int)\n{",
        "class Target\n{",
        "class Target(val value: Int) : Base()\n{",
        "class Target(val value: Int)\n    : Base()\n{",
        "class Target(val value: Int) : First, Second\n{",
        "class Target<T>(val value: T)\n/* body */\n{",
    ])
    func bodyBelongsToClassInCSTAndAST(header: String) throws {
        let declaration = "\(header)\n    fun read(): Int = 7\n}"
        let source = "\(declaration)\nclass Following\nfun after() = 1"
        let parsed = parse(source)
        let roots = parsed.arena.children(of: parsed.root).compactMap { child -> NodeID? in
            guard case let .node(id) = child else { return nil }
            return id
        }
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .kotlinFile)
        #expect(roots.map { parsed.arena.node($0).kind } == [.classDecl, .classDecl, .funDecl])
        let targetID = try #require(roots.first)
        #expect(parsed.arena.node(targetID).range.end.offset == declaration.utf8.count)
        let bodyID = try #require(parsed.arena.children(of: targetID).compactMap { child -> NodeID? in
            guard case let .node(id) = child, parsed.arena.node(id).kind == .block else { return nil }
            return id
        }.first)
        #expect(parsed.arena.children(of: bodyID).compactMap { child -> SyntaxKind? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id).kind
        } == [.funDecl])

        let (ast, ctx) = try buildASTModule(from: source, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let target = try #require(firstClassDecl(named: "Target", in: ast, interner: ctx.interner))
        #expect(target.range.end.offset == declaration.utf8.count)
        #expect(target.memberFunctions.count == 1)
        let member = try #require(target.memberFunctions.first)
        guard case let .funDecl(read) = ast.arena.decl(member) else {
            Issue.record("Expected member function")
            return
        }
        #expect(ctx.interner.resolve(read.name) == "read")
        _ = try #require(firstClassDecl(named: "Following", in: ast, interner: ctx.interner))
        _ = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
        let file = try #require(ast.files.first)
        #expect(file.topLevelDecls.compactMap { id -> String? in
            switch ast.arena.decl(id) {
            case let .classDecl(declaration):
                return ctx.interner.resolve(declaration.name)
            case let .funDecl(declaration):
                return ctx.interner.resolve(declaration.name)
            default:
                return nil
            }
        } == ["Target", "Following", "after"])
    }

    @Test(arguments: ["println(7)", "val result = 7\nprintln(result)", "{ println(7) }", "+7"])
    func bodyDoesNotAbsorbFollowingScriptStatement(statement: String) throws {
        let declaration = "class Target(val value: Int)\n{\n    fun read() = value\n}"
        let parsed = parse("\(declaration)\n\(statement)")
        let roots = parsed.arena.children(of: parsed.root).compactMap { child -> SyntaxNode? in
            guard case let .node(id) = child else { return nil }
            return parsed.arena.node(id)
        }
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .script)
        #expect(roots.first?.kind == .classDecl)
        #expect(roots.first?.range.end.offset == declaration.utf8.count)
        #expect(roots.count >= 2)
        #expect(try #require(roots.last).range.start.offset >= declaration.utf8.count)
    }

    @Test
    func semicolonBeforeBlockKeepsBlockOutsideClass() {
        let declaration = "class Target(val value: Int);"
        let parsed = parse("\(declaration)\n{ println(7) }")
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.node(parsed.root).kind == .script)
        #expect(parsed.arena.nodes.first { $0.kind == .classDecl }?.range.end.offset == declaration.utf8.count)
    }
}
#endif
