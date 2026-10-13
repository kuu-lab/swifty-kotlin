#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func testSyntheticReceiverExtensionPropertiesCaptureBoundReceiver() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*
        import kotlinx.coroutines.test.*

        class Other
        val Other.probe: Long
            get() = 17L
        val TestScope.probe: Long
            get() = this.currentTime
        val CoroutineScope.scopeProbe: Boolean
            get() = coroutineContext != null

        @OptIn(ExperimentalCoroutinesApi::class)
        fun main() {
            runTest {
                println(coroutineContext)
                println(testScheduler)
                println(probe)
                println(scopeProbe)
                listOf(1).forEach {
                    println(probe)
                    println(scopeProbe)
                }
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let scope = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlinx"), ctx.interner.intern("coroutines"),
            ctx.interner.intern("test"), ctx.interner.intern("TestScope"),
        ]))
        let properties = ["probe", "scopeProbe"].flatMap { name in
            sema.symbols.lookupAll(fqName: [ctx.interner.intern(name)])
        }
        let getters = properties.compactMap { property -> SymbolID? in
            guard let receiver = sema.symbols.extensionPropertyReceiverType(for: property),
                  let scopeType = sema.symbols.propertyType(for: scope),
                  sema.types.isSubtype(scopeType, receiver)
            else { return nil }
            return sema.symbols.extensionPropertyGetterAccessor(for: property)
        }
        #expect(getters.count == 2)
        let lambdas = try findKIRLambdaFunctions(in: ctx).filter { function in
            function.body.contains { instruction in
                    guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                    return getters.contains(symbol)
                }
        }
        #expect(lambdas.count == 2, "Both direct and nested property reads must invoke getters")
        for lambda in lambdas {
            #expect(lambda.params.contains { parameter in
                guard case let .classType(type) = sema.types.kind(of: parameter.type) else { return false }
                return type.classSymbol == scope
            }, "The nested lambda must capture the TestScope receiver")
            for getter in getters {
                #expect(lambda.body.contains { instruction in
                    guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                          symbol == getter, arguments.count == 1,
                          let receiverType = module.arena.exprType(arguments[0]),
                          case let .classType(type) = sema.types.kind(of: receiverType)
                    else { return false }
                    return type.classSymbol == scope
                })
            }
            #expect(!lambda.body.contains { instruction in
                guard case let .loadGlobal(_, symbol) = instruction else { return false }
                return properties.contains(symbol)
            })
        }
    }
}
#endif
