#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CompanionObjectNameBoundaryTests {
    @Test(arguments: [
        "object Token", "class Token", "interface Token", "fun token() = 2",
        "val token = 2", "var token = 2",
    ])
    func unnamedBodylessCompanionPreservesFollowingDeclaration(declaration: String) throws {
        let parsed = parse("class Host {\n    companion object\n    \(declaration)\n}")
        let companionIndex = try #require(parsed.arena.nodes.firstIndex { $0.kind == .objectDecl })
        let companionID = NodeID(rawValue: Int32(companionIndex))
        let headerTokens = parsed.arena.children(of: companionID).compactMap { child -> TokenKind? in
            guard case let .token(id) = child else { return nil }
            return parsed.arena.token(id)?.kind
        }
        let blockIndex = try #require(parsed.arena.nodes.firstIndex { $0.kind == .block })
        let members = parsed.arena.children(of: NodeID(rawValue: Int32(blockIndex))).compactMap { child -> NodeID? in
            guard case let .node(id) = child else { return nil }
            return id
        }

        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(headerTokens == [.keyword(.companion), .keyword(.object)])
        #expect(members.count == 2)
        #expect(members.first == companionID)
    }

    @Test(arguments: [
        ("", ""), (" {}", ""), (" Named", "Named"), ("\nNamed", "Named"),
        ("\n`object`", "object"), ("\n`when`", "when"), ("\nget", "get"),
        ("\ncontext", "context"), ("\ndata", "data"), ("\ncompanion", "companion"),
        ("\nimport", "import"), ("\nconstructor", "constructor"),
    ])
    func companionAndNestedObjectRetainTheirASTNames(header: String, name: String) throws {
        let ctx = makeContextFromSource("class Host {\n    companion object\(header)\n    object Token\n}")
        try runFrontend(ctx)
        let ast = try #require(ctx.ast)
        let host = try #require(firstClassDecl(named: "Host", in: ast, interner: ctx.interner))
        let companionID = try #require(host.companionObject)
        guard case let .objectDecl(companion)? = ast.arena.decl(companionID) else {
            Issue.record("Expected a companion object declaration")
            return
        }
        let tokenID = try #require(host.nestedObjects.first)
        guard case let .objectDecl(token)? = ast.arena.decl(tokenID) else {
            Issue.record("Expected a nested object declaration")
            return
        }

        // BuildAST leaves an omitted name empty; Sema supplies "Companion".
        #expect(ctx.diagnostics.diagnostics.isEmpty)
        #expect(ctx.interner.resolve(companion.name) == name)
        #expect(companion.modifiers.contains(.companion))
        #expect(host.nestedObjects.count == 1)
        #expect(ctx.interner.resolve(token.name) == "Token")
    }

    @Test(arguments: [
        ("companion object\nobject Token", "Companion"),
        ("companion object {}\nobject Token", "Companion"),
        ("companion object Named\nobject Token", "Named"),
        ("object Token\ncompanion object", "Companion"),
    ])
    func companionAndNestedObjectTypesResolve(members: String, name: String) throws {
        let ctx = makeContextFromSource("""
        class Host { \(members) }
        fun Host.\(name).first(): Int = 1
        fun Host.Token.second(): Int = 2
        fun firstTyped(value: Host.\(name)): Int = 1
        fun secondTyped(value: Host.Token): Int = 2
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        #expect(sema.symbols.lookup(fqName: ["Host", name].map(ctx.interner.intern)) != nil)
        #expect(sema.symbols.lookup(fqName: ["Host", "Token"].map(ctx.interner.intern)) != nil)
    }

    @Test
    func unknownQualifiedObjectTypeIsStillRejected() throws {
        let ctx = makeContextFromSource("""
        class Host { object Token }
        fun Host.Missing.identify(): Int = 1
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0025" && $0.message.contains("Missing")
        })
    }

    @Test
    func originalNestedReceiverConformanceProgramResolves() throws {
        // Unmodified JetBrains/kotlin v2.3.10 fixture (Apache-2.0), commit
        // 679366a83f99851b42f64795f10ed803ff011c73, compiler/testData/codegen/box/
        // extensionFunctions/extensionFunctionWithNestedReceiver.kt.
        let ctx = makeContextFromSource("""
        class A {
            class B
            companion object
            object C
            inner class D
        }

        fun A.B.foo(): Boolean {
            return true
        }

        fun A.Companion.foo(): Boolean {
            return true
        }

        fun A.C.foo(): Boolean {
            return true
        }

        fun A.D.foo(): Boolean {
            return true
        }

        fun box(): String {
            return if (A.B().foo() && A.foo() && A.C.foo() && A().D().foo()) "OK" else "fail"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
