#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct ImplicitReceiverExtensionCallTests {
    @Test(arguments: ["launch", "async"])
    func suspendReceiverLambdaArgumentResolvesInsideExtension(name: String) throws {
        let ctx = makeContextFromSource("""
        interface CC
        interface Job
        interface CScope { val ctx: CC }
        fun CScope.\(name)(context: CC, block: suspend CScope.() -> Unit): Job = TODO()

        fun CScope.reader(coroutineContext: CC) {
            val a = \(name)(coroutineContext) { val context: CC = ctx }
            val b = this.\(name)(coroutineContext) { val context: CC = ctx }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: name, in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName == [ctx.interner.intern(name)])
        let lambda = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        #expect(!sema.bindings.isCoroutineLauncherLambdaExpr(lambda))
    }

    @Test func noArgumentExtensionCallBindsImplicitReceiver() throws {
        let ctx = makeContextFromSource("""
        interface Source
        fun Source.readCodePointValue(): Int = 42
        fun Source.readUtf8ExactCharacters(): Int = readCodePointValue()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "readCodePointValue", in: ast, interner: ctx.interner))
        #expect(sema.bindings.implicitReceiverMemberNames[call] != nil)
    }

    @Test func incompatibleImplicitReceiverStillRejectsExtension() throws {
        let ctx = makeContextFromSource("""
        interface Source
        interface Other
        fun Source.readCodePointValue(): Int = 42
        fun Other.readUtf8ExactCharacters(): Int = readCodePointValue()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }
}
#endif
