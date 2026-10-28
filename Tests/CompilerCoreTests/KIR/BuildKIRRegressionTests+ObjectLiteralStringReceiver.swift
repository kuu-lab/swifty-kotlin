#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test(arguments: [false, true])
    func testObjectLiteralCapturesImplicitStringReceiver(nested: Bool) throws {
        let source = nested ? """
        interface Reader { fun read(): Int }
        interface Factory { fun make(): Reader }
        fun String.reader(): Factory = object : Factory {
            override fun make(): Reader = object : Reader {
                override fun read(): Int = get(0).code
            }
        }
        """ : """
        interface Reader { fun read(): Int }
        fun String.reader(): Reader = object : Reader {
            override fun read(): Int = get(0).code
        }
        fun main() { println("A".reader().read()) }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let reader = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("reader")]))
        let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: reader)
        let receiverType = try #require(sema.symbols.functionSignature(for: reader)?.receiverType)
        let getCall = try #require(nameRefCallExprID(named: "get", in: ast, interner: ctx.interner))
        #expect(sema.bindings.implicitReceiverOuterReceiver(for: getCall) == receiverSymbol)

        let capturingObjects = sema.symbols.allSymbols().filter {
            sema.bindings.objectLiteralCaptureSymbols(for: $0.id).contains(receiverSymbol)
        }
        #expect(capturingObjects.count == (nested ? 2 : 1))
        for object in capturingObjects {
            #expect(sema.symbols.nominalLayout(for: object.id)?.fieldOffsets[receiverSymbol] != nil)
        }
        #expect(sema.bindings.capturedLocalType(for: receiverSymbol) == receiverType)

        let getBinding = try #require(sema.bindings.callBinding(for: getCall))
        let read = try #require(findAllKIRFunctions(in: module).first { function in
            ctx.interner.resolve(function.name) == "read" && function.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == getBinding.chosenCallee
            }
        })
        let receiver = try #require(read.body.compactMap { instruction -> KIRExprID? in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                  symbol == getBinding.chosenCallee else { return nil }
            return arguments.first
        }.first)
        #expect(module.arena.exprType(receiver) == receiverType)
        // The value must be loaded from the capture field in this member body.
        #expect(read.body.contains { instruction in
            guard case let .call(_, callee, _, result, _, _, _, _) = instruction else { return false }
            return ctx.interner.resolve(callee) == "kk_array_get_inbounds" && result == receiver
        })
    }
}
#endif
