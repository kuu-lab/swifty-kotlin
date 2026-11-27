#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct FunctionReturnTypeNewlineTests {
    @Test(arguments: [
        "fun f()\n    : Int { return 1 }",
        "class C {\n    fun f()\n        : Int { return 1 }\n}",
        "class R\nfun R.unique()\n    : R { return this }",
        "class R\nfun R.unique()\n    : R = this",
        "class Box<A>(val a: A)\nfun <T> Box<T>.unique()\n    : Box<T> { return this }",
        "class Box<A, B, C>(val a: A)\nfun <T, E, V> Box<List<T>, E, V>.unique()\n    : Box<Set<T>, E, V> { return this as Box<Set<T>, E, V> }",
        "class C {\n    fun <T> List<T>.size2()\n        : Int { return 2 }\n}",
        "class Box<A>(val a: A)\nfun <T> Box<T>.unique()\n    : Box<T>\n    where T : Any { return this }",
        "class R\nval R.x\n    : Int\n    get() = 1",
        "class R\nval R.x\n    : Int = 1",
        "val x\n    : Int\n    by lazy { 1 }",
        "val x by object\n    : D { }",
    ])
    func newlineTypeColonParses(source: String) {
        let parsed = parse(source)

        #expect(parsed.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(parsed.diagnostics.diagnostics)")
    }

    @Test
    func genericExtensionReceiverKeepsReturnTypeAndBody() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class Box<A, B, C>(val a: A)
        fun <T, EachT, ValueT> Box<List<T>, EachT, ValueT>.unique()
                : Box<Set<T>, EachT, ValueT> {
            return this as Box<Set<T>, EachT, ValueT>
        }
        fun after() = 1
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let unique = try #require(firstFunDecl(named: "unique", in: ast, interner: ctx.interner))
        #expect(unique.returnType != nil)
        #expect(unique.body != .unit)
        _ = try #require(firstFunDecl(named: "after", in: ast, interner: ctx.interner))
    }

    @Test
    func extensionPropertyKeepsDeclaredType() throws {
        let (ast, ctx) = try buildASTModule(from: """
        class R
        val R.x
            : Int
            get() = 1
        """, includeStdlib: false)
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        let property = try #require(ast.arena.declarations().compactMap { decl -> PropertyDecl? in
            guard case let .propertyDecl(property) = decl,
                  ctx.interner.resolve(property.name) == "x" else { return nil }
            return property
        }.first)
        #expect(property.type != nil)
    }

    @Test
    func colonAfterExpressionBodyIsNotAbsorbed() {
        let parsed = parse("""
        fun f() = 1
            : Int
        """)

        #expect(parsed.arena.node(parsed.root).kind == .script)
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 1)
        #expect(parsed.arena.nodes.contains { $0.kind == .statement })
    }

    @Test
    func colonAfterDelegationByIsNotAbsorbed() {
        let parsed = parse("""
        val x by foo()
            : Int
        """)

        #expect(parsed.arena.node(parsed.root).kind == .script)
        #expect(parsed.arena.nodes.contains { $0.kind == .propertyDecl })
        #expect(parsed.arena.nodes.contains { $0.kind == .statement })
    }

    @Test
    func followingDeclarationIsNotAbsorbed() {
        let parsed = parse("""
        class R
        fun R.unique()
            : R {
            return this
        }
        fun after() = 1
        """)

        #expect(parsed.diagnostics.diagnostics.isEmpty,
                "Unexpected diagnostics: \(parsed.diagnostics.diagnostics)")
        #expect(parsed.arena.nodes.count { $0.kind == .funDecl } == 2)
        #expect(parsed.arena.nodes.count { $0.kind == .classDecl } == 1)
    }
}
#endif
