#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite struct ImplicitReceiverMemberScopeFallbackTests {
    private func makeIsolatedContext(_ source: String) -> CompilationContext {
        makeIsolatedContext([source])
    }

    private func makeIsolatedContext(_ sources: [String]) -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = sources.indices.map { directory.appendingPathComponent("input\($0).kt").path }
        let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }

    @Test(arguments: [
        "fun S.read(n: Int): String",
        "fun read(s: S, n: Int): String",
    ])
    func requireFallsThroughToBundledTopLevelOverload(declaration: String) throws {
        let source = """
        interface S { fun require(n: Long) }
        \(declaration) {
            require(n >= 0) { "neg: $n" }
            return "a"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(nameRefCallExprID(named: "require", in: ast, interner: ctx.interner))
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["kotlin", "require"])
            #expect(sema.bindings.implicitReceiverMemberNames[call] == nil)
        }
    }

    @Test(arguments: ["require", "acquire"])
    func inapplicableMemberDoesNotHideTopLevelFunction(memberName: String) throws {
        let ctx = makeIsolatedContext("""
        interface S { fun \(memberName)(n: Long) }
        fun require(value: Boolean, message: () -> String) {}
        fun S.read(n: Int): String {
            require(n >= 0) { "neg: $n" }
            return "a"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "require", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["require"])
        #expect(sema.bindings.implicitReceiverMemberNames[call] == nil)
    }

    @Test func fallbackContextualizesImplicitLambdaParameter() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun convert(n: Long, block: (Long) -> Long): Long }
        fun convert(value: Boolean, block: (String) -> String): String = block("ok")
        fun S.read(): String = convert(true) { it }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "convert", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["convert"])
        let lambda = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        let lambdaType = try #require(sema.bindings.exprType(for: lambda))
        guard case let .functionType(function) = sema.types.kind(of: lambdaType) else {
            Issue.record("Expected contextual function type")
            return
        }
        #expect(function.params == [sema.types.stringType])
        #expect(function.returnType == sema.types.stringType)
    }

    @Test func inapplicableClassMemberDoesNotHideOuterScopeFunction() throws {
        let ctx = makeIsolatedContext("""
        fun require(value: Boolean, message: () -> String) {}
        class S {
            fun require(n: Long) {}
            fun read(n: Int): String {
                require(n >= 0) { "neg: $n" }
                return "a"
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "require", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["require"])
        #expect(sema.bindings.implicitReceiverMemberNames[call] == nil)
    }

    @Test func applicableMemberKeepsPrecedenceOverMoreSpecificTopLevelFunction() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun pick(value: Any): Int }
        fun pick(value: String): String = value
        fun S.read(): Int = pick("ok")
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "pick", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["S", "pick"])
        #expect(sema.bindings.implicitReceiverMemberNames[call] != nil)
    }

    @Test func conditionalIntegerArgumentRetainsMemberContext() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun pick(value: Long): Int }
        fun pick(value: Int): String = "outer"
        fun S.read(): Int = pick(if (true) 1 else 2)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "pick", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["S", "pick"])
    }

    @Test func nestedCallRetainsMemberExpectedReceiverType() throws {
        let ctx = makeIsolatedContext("""
        class Text(val length: Int)
        class Box<T>
        fun <T> wrap(block: T.() -> Int): Box<T> = Box<T>()
        class S(val length: Int) { fun pick(box: Box<Text>): Int = 7 }
        fun pick(box: Int): Int = 0
        fun S.read(): Int = pick(wrap { length })
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "pick", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["S", "pick"])
        let length = try lambdaLengthExpr(in: ast)
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: length) == nil)
    }

    private func lambdaLengthExpr(in ast: ASTModule) throws -> ExprID {
        let lambda = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        let lambdaBody: ExprID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(lambda) { body } else { nil }
        let body = try #require(lambdaBody)
        if case let .blockExpr(statements, trailing, _) = ast.arena.expr(body) {
            return try #require(trailing ?? statements.last)
        }
        return body
    }

    @Test func samMemberKeepsPrecedence() throws {
        let ctx = makeIsolatedContext("""
        fun interface Action { fun run(n: Int): Int }
        interface S { fun choose(block: Action): Int }
        fun choose(block: (Int) -> Int): String = "outer"
        fun S.read(): Int = choose { n -> n }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "choose", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["S", "choose"])
    }

    @Test func samFunctionValueDoesNotSelectTopLevelFunction() throws {
        let ctx = makeIsolatedContext("""
        fun interface Action { fun run(n: Int): Int }
        interface S { fun choose(block: Action): Int }
        fun choose(block: (Int) -> Int): String = "outer"
        fun S.read(action: (Int) -> Int): Int = choose(action)
        """)
        try runSema(ctx)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "choose", in: ast, interner: ctx.interner))
        let topLevel = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("choose")]))
        let chosen = sema.bindings.callBinding(for: call)?.chosenCallee
        #expect(chosen != topLevel)
        if let chosen {
            #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["S", "choose"])
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        } else {
            // KUU-1972 tracks the existing function-value SAM conversion gap.
            // Until conversion succeeds, keep the member's error rather than
            // incorrectly resolving the same-name top-level function.
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
        }
    }

    @Test func fallbackLambdaDoesNotRetainInapplicableMemberReceiver() throws {
        let ctx = makeIsolatedContext("""
        class A
        class Text(val length: Int)
        class S(val length: Int) {
            fun convert(n: Long, block: A.() -> Int): Int = 0
        }
        fun convert(value: Boolean, block: Text.() -> Int): Int = Text(2).block()
        fun S.read(): Int = convert(true) { length }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let length = try lambdaLengthExpr(in: ast)
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: length) == nil)
        let symbol = try #require(sema.bindings.identifierSymbols[length])
        #expect(sema.symbols.symbol(symbol)?.fqName.map { ctx.interner.resolve($0) } == ["Text", "length"])
    }

    @Test func ambiguousMemberOverloadsDoNotFallThrough() throws {
        let ctx = makeIsolatedContext("""
        interface S {
            fun pick(value: String?, other: Any?): Int
            fun pick(value: Any?, other: String?): Int
        }
        fun pick(value: Any?, other: Any?): String = "outer"
        fun S.read() { pick(null, null) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0003" })
    }

    @Test func incompatibleExpectedReturnTypeDoesNotSelectTopLevelFunction() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun pick(value: Any): Int }
        fun pick(value: String): String = value
        fun S.read(): String = pick("ok")
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "An applicable member must keep precedence despite its return type")
    }

    @Test(arguments: ["import lib.pick", "import lib.*"])
    func inapplicableMemberFallsThroughToImportedFunction(imports: String) throws {
        let ctx = makeIsolatedContext([
            "package lib; fun pick(value: Boolean): String = \"outer\"",
            """
            package app
            \(imports)
            interface S { fun pick(value: Long): Int }
            fun S.read(): String = pick(true)
            """,
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "pick", in: ast, interner: ctx.interner))
        let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
        #expect(sema.symbols.symbol(chosen)?.fqName.map { ctx.interner.resolve($0) } == ["lib", "pick"])
        #expect(sema.bindings.implicitReceiverMemberNames[call] == nil)
    }

    @Test func callableLocalStillShadowsTopLevelFunction() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun pick(value: Long): Int }
        fun pick(value: Boolean): String = "outer"
        fun S.read() {
            fun pick(value: Long): Int = 7
            pick(true)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func inapplicableTopLevelFunctionStillRejectsCall() throws {
        let ctx = makeIsolatedContext("""
        interface S { fun pick(value: Long): Int }
        fun pick(value: String): String = value
        fun S.read() { pick(true) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }

    @Test func filePrivateTopLevelFunctionRemainsUnavailable() throws {
        let ctx = makeIsolatedContext([
            "package lib; interface S { fun pick(value: Long): Int }; private fun pick(value: Boolean): Int = 7",
            "package lib; fun S.read() { pick(true) }",
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }
}
#endif
