#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExtensionFunctionLabelTests {
    @Test(arguments: [false, true])
    func qualifiedExtensionReceiverIsCapturedBySuspendReceiverLambda(fullyLowered: Bool) throws {
        let ctx = makeContextFromSource("""
        interface CC
        interface CScope { val ctx: CC }
        class Job

        fun CScope.reader(coroutineContext: CC) {
            val direct = this@reader.ctx
            val job = launch2(coroutineContext) {
                val inner = this@reader.ctx
                val own = this.ctx
            }
        }
        fun CScope.launch2(context: CC, block: suspend CScope.() -> Unit): Job = TODO()
        """)
        if fullyLowered {
            try runToLowering(ctx)
        } else {
            try runToKIR(ctx)
        }
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let reader = try #require(sema.symbols.allSymbols().first {
            ctx.interner.resolve($0.name) == "reader" && $0.kind == .function
        })
        let receiver = SyntheticSymbolScheme.receiverParameterSymbol(for: reader.id)
        let receiverType = try #require(sema.symbols.functionSignature(for: reader.id)?.receiverType)
        let qualifiedRefs = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .thisRef(label?, _) = expr,
                  ctx.interner.resolve(label) == "reader" else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(qualifiedRefs.count == 2)
        for ref in qualifiedRefs {
            #expect(sema.bindings.identifierSymbol(for: ref) == receiver)
            #expect(sema.bindings.exprType(for: ref) == receiverType)
        }
        let lambda = try #require(ast.arena.exprs.enumerated().first { _, expr in
            if case let .lambdaLiteral(_, _, label?, _) = expr {
                return ctx.interner.resolve(label) == "launch2"
            }
            return false
        })
        let lambdaID = ExprID(rawValue: Int32(lambda.offset))
        #expect(sema.bindings.captureSymbolsByExpr[lambdaID]?.contains(receiver) == true)
        let ownReceiver = SyntheticSymbolScheme.lambdaReceiverSymbol(for: lambdaID)
        let unqualifiedRefs = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            guard case let .thisRef(nil, range) = expr,
                  range.start.file == reader.declSite?.start.file else { return nil }
            return ExprID(rawValue: Int32(index))
        }
        #expect(unqualifiedRefs.count == 1)
        for ref in unqualifiedRefs {
            #expect(sema.bindings.identifierSymbol(for: ref) == ownReceiver)
        }
        _ = try #require(ctx.kir)
    }

    @Test func unknownExtensionReceiverLabelIsRejected() throws {
        let ctx = makeContextFromSource("""
        class Scope
        fun Scope.reader() { val receiver = this@missing }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0053", in: ctx)
    }
}
#endif
