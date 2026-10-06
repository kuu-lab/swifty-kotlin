#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func importedCompanionExtensionPropertyCarriesSingletonReceiver() throws {
        let ctx = makeContextFromSources([
            """
            package factories
            class Factory {
                companion object {
                    val Int.score: Int get() = this + 10
                }
            }
            """,
            """
            import factories.Factory.Companion.score
            fun main() { println(2.score) }
            """,
        ])
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let getter = try #require(findAllKIRFunctions(in: module).first {
            ctx.interner.resolve($0.name) == "get"
                && sema.symbols.memberExtensionOwnerSymbol(for: $0.symbol) != nil
        })
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let call = try #require(body.first {
            if case let .call(symbol, _, _, _, _, _, _, _) = $0 {
                return symbol == getter.symbol
            }
            return false
        })
        if case let .call(_, _, arguments, _, _, _, _, _) = call {
            #expect(arguments.count == getter.params.count)
            #expect(arguments.count == 2)
            let receiver = try #require(arguments.first)
            #expect(module.arena.exprType(receiver) == getter.params[0].type)
        }
    }

    @Test
    func memberExtensionPropertyAccessorsCarryBothReceivers() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            var stored: Int = 0
            var Int.score: Int
                get() = this + offset + stored
                set(value) { stored = value - this - offset }
            fun use() { 2.score = 10; 2.score += 3; println(2.score) }
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let functions = findAllKIRFunctions(in: module)
        let getter = try #require(functions.first { ctx.interner.resolve($0.name) == "get" })
        let setter = try #require(functions.first { ctx.interner.resolve($0.name) == "set" })
        let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: getter.symbol))
        #expect(sema.symbols.memberExtensionOwnerSymbol(for: setter.symbol) == owner)
        #expect(getter.params.count == 2)
        #expect(setter.params.count == 3)
        #expect(sema.types.kind(of: getter.params[0].type) == .classType(ClassType(
            classSymbol: owner, args: [], nullability: .nonNull
        )))
        #expect(sema.types.kind(of: getter.params[1].type) == .primitive(.int, .nonNull))
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        var getterCalls = 0
        var setterCalls = 0
        for instruction in body {
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction {
                if symbol == getter.symbol {
                    getterCalls += 1
                    #expect(arguments.count == 2)
                }
                if symbol == setter.symbol {
                    setterCalls += 1
                    #expect(arguments.count == 3)
                }
            }
        }
        #expect(getterCalls == 2)
        #expect(setterCalls == 2)
    }

    @Test
    func memberExtensionPropertyLambdaCapturesDispatchReceiver() throws {
        let ctx = makeContextFromSource("""
        class C(private val offset: Int) {
            val Int.score: Int get() = this + offset
            fun use(): Int { val block = { 3.score }; return block() }
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let getter = try #require(functions.first { ctx.interner.resolve($0.name) == "get" })
        let lambda = try #require(functions.first {
            ctx.interner.resolve($0.name).hasPrefix("kk_lambda_")
        })
        #expect(lambda.params.count == 1)
        #expect(lambda.body.contains { instruction in
            if case let .call(symbol, _, arguments, _, _, _, _, _) = instruction {
                return symbol == getter.symbol && arguments.count == 2
            }
            return false
        })
    }


    @Test
    func memberExtensionPropertyVirtualGetterUsesDispatchReceiver() throws {
        let ctx = makeContextFromSource("""
        open class Base {
            open val Int.score: Int get() = this + 10
            fun use(): Int = 2.score
        }
        class Derived : Base() {
            override val Int.score: Int get() = this + 20
        }
        """)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let body = try findKIRFunctionBody(named: "use", in: module, interner: ctx.interner)
        let call = try #require(body.first { instruction in
            if case .virtualCall = instruction { return true }
            return false
        })
        if case let .virtualCall(symbol, _, receiver, arguments, _, _, _, _) = call {
            let accessor = try #require(symbol)
            let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: accessor))
            #expect(sema.types.kind(of: try #require(module.arena.exprType(receiver))) == .classType(ClassType(
                classSymbol: owner, args: [], nullability: .nonNull
            )))
            #expect(arguments.count == 1)
            #expect(sema.types.kind(of: try #require(module.arena.exprType(arguments[0]))) == .primitive(.int, .nonNull))
        }
    }

}
#endif
