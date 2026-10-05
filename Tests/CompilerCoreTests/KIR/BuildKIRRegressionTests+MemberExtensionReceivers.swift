#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func memberExtensionHasDispatchAndExtensionReceiverParameters() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            fun Int.plusOffset(): Int = this + offset
            fun use(n: Int): Int = n.plusOffset()
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let function = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "plusOffset"
        })
        #expect(function.params.count == 2)
        let sema = try #require(ctx.sema)
        #expect(sema.symbols.symbol(function.symbol)?.flags.contains(.localFunction) == false)
        #expect(sema.types.kind(of: function.params[1].type) == .primitive(.int, .nonNull))
        let owner = try #require(sema.symbols.parentSymbol(for: function.symbol))
        #expect(sema.types.kind(of: function.params[0].type) == .classType(ClassType(
            classSymbol: owner, args: [], nullability: .nonNull
        )))
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        #expect(body.contains { instruction in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction {
                return symbol == function.symbol && arguments.count == 2
            }
            return false
        })
    }

    @Test
    func memberExtensionDefaultStubForwardsBothReceivers() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            fun Int.plusOffset(extra: Int = offset): Int = this + offset + extra
            fun use(n: Int): Int = n.plusOffset()
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let stub = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "plusOffset$default"
        })
        #expect(stub.params.count == 4)
        #expect(stub.body.contains { instruction in
            if case let .call(_, callee, arguments, _, _, _, _, _) = instruction {
                return ctx.interner.resolve(callee) == "plusOffset" && arguments.count == 3
            }
            return false
        })
    }

    @Test
    func memberExtensionCallInsideLambdaCapturesDispatchReceiver() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            fun Int.plusOffset(): Int = this + offset
            fun use(n: Int): Int {
                val block = { n.plusOffset() }
                return block()
            }
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let member = try #require(functions.first {
            ctx.interner.resolve($0.name) == "plusOffset"
        })
        let lambda = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("kk_lambda_")
        })
        #expect(lambda.params.count == 2)
        #expect(lambda.body.contains { instruction in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction {
                return symbol == member.symbol && arguments.count == 2
            }
            return false
        })
    }

    @Test
    func memberExtensionReturnedLambdaCapturesBothReceivers() throws {
        let ctx = makeContextFromSource("""
        class C(private var offset: Int) {
            fun Int.capture(): () -> Int = { this + offset }
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let lambda = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name).hasPrefix("kk_lambda_")
        })
        #expect(lambda.params.count == 2)
        let sema = try #require(ctx.sema)
        #expect(lambda.params.contains {
            if case .classType = sema.types.kind(of: $0.type) { return true }
            return false
        })
        #expect(lambda.params.contains {
            sema.types.kind(of: $0.type) == .primitive(.int, .nonNull)
        })
    }

    @Test
    func memberExtensionLambdaKeepsSameTypedReceiversDistinct() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            fun C.capture(): () -> Int = { offset + this@C.offset }
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let lambda = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name).hasPrefix("kk_lambda_")
        })
        #expect(lambda.params.count == 2)
        let propertyReceivers = lambda.body.compactMap { instruction -> KIRExprID? in
            if case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
               ctx.interner.resolve(callee) == "kk_array_get_inbounds"
            {
                return arguments.first
            }
            return nil
        }
        #expect(Set(propertyReceivers).count == 2)
    }

    @Test
    func memberExtensionOnOwnerTypeIsNotAnOrdinaryMember() throws {
        let ctx = makeContextFromSource("""
        class C(val offset: Int) {
            fun C.sum(): Int = offset + this@C.offset
            fun use(other: C): Int = other.sum()
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let function = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "sum"
        })
        #expect(function.params.count == 2)
        let sema = try #require(ctx.sema)
        #expect(sema.symbols.memberExtensionOwnerSymbol(for: function.symbol) != nil)
    }
}
#endif
