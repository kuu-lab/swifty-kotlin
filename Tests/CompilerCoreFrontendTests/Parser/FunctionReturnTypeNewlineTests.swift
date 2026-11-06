#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-4080 / KUU-4083: the `:` introducing a function return type or a
/// property declared type may start on the line after the signature
/// (`fun R.f()\n    : R`). kotlinc accepts this style — clikt's
/// `parameters/options/TransformAll.kt` / `TransformEach.kt` use it — but a
/// signature whose tail already consumed receiver tokens (`.unique()`,
/// `<T> Box<T>.f()`) used to end the declaration at the newline, leaving the
/// `:` line to fail with KSWIFTK-PARSE-0025.
@Suite
struct FunctionReturnTypeNewlineTests {
    @Test(arguments: [
        // Plain and member functions already worked; keep them pinned.
        "fun f()\n    : Int { return 1 }",
        "class C {\n    fun f()\n        : Int { return 1 }\n}",
        // Extension receivers leave `.name()` for the declaration tail, which
        // is what used to break the newline-colon continuation.
        "class R\nfun R.unique()\n    : R { return this }",
        "class R\nfun R.unique()\n    : R = this",
        "class Box<A>(val a: A)\nfun <T> Box<T>.unique()\n    : Box<T> { return this }",
        "class Box<A, B, C>(val a: A)\nfun <T, E, V> Box<List<T>, E, V>.unique()\n    : Box<Set<T>, E, V> { return this as Box<Set<T>, E, V> }",
        "class C {\n    fun <T> List<T>.size2()\n        : Int { return 2 }\n}",
        // A `where` clause may follow the next-line return type.
        "class Box<A>(val a: A)\nfun <T> Box<T>.unique()\n    : Box<T>\n    where T : Any { return this }",
        // Extension property declared types share the same tail position.
        "class R\nval R.x\n    : Int\n    get() = 1",
        "class R\nval R.x\n    : Int = 1",
        // KUU-4333: a declared type may also precede a delegation `by`, and an
        // `object` literal delegate keeps its own supertype colon on the next
        // line (`val x by object\n    : D { }`).
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
        // `=` already ended the signature: a `:` on the next line cannot be a
        // return type and must remain a stray top-level statement — which is
        // what the driver later rejects with KSWIFTK-PARSE-0025 — matching
        // kotlinc's rejection of `fun f() = 1\n    : Int`.
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
        // KUU-4333: once `by` starts a delegate expression the signature
        // region is over. A `:` on the next line cannot be a declared type —
        // kotlinc rejects `val x by foo()\n    : Int` with "Expecting a top
        // level declaration" — so the colon must stay a stray top-level
        // statement (which the driver later rejects with KSWIFTK-PARSE-0025)
        // instead of being absorbed into the delegate expression where it
        // would be silently dropped.
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
