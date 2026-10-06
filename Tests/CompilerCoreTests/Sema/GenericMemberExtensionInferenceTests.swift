@testable import CompilerCore
import Testing

@Suite
struct GenericMemberExtensionInferenceTests {
    @Test(arguments: ["n.getOffset()", "n.getOffset<String>(\"x\")", "getOffset()"])
    func classTypeParameterRemainsLexical(call: String) throws {
        let implicit = call == "getOffset()"
        let extensionDecl = call.contains("String")
            ? "fun <U> Int.getOffset(unused: U): T = offset"
            : "fun Int.getOffset(): T = offset"
        let runDecl = implicit
            ? "fun Int.run(): T = \(call)"
            : "fun run(n: Int): T = \(call)"
        let ctx = makeContextFromSource("""
        class GenericOffset<T>(private val offset: T) {
            \(extensionDecl)
            \(runDecl)
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let run = try findKIRFunction(named: "run", in: module, interner: ctx.interner)
        let getOffset = try findKIRFunction(named: "getOffset", in: module, interner: ctx.interner)
        #expect(run.returnType == getOffset.returnType)
        let signature = try #require(sema.symbols.functionSignature(for: getOffset.symbol))
        #expect(signature.classTypeParameterCount == 1)
        let binding = try #require(sema.bindings.callBindings.values.first { $0.chosenCallee == getOffset.symbol })
        #expect(binding.substitutedTypeArguments.first == getOffset.returnType)
    }

    @Test
    func inheritedExtensionUsesConcreteDispatchType() throws {
        let ctx = makeContextFromSource("""
        open class GenericOffset<T>(private val offset: T) {
            fun Int.getOffset(): T = offset
        }
        class DerivedOffset : GenericOffset<String>("value") {
            fun run(n: Int): String = n.getOffset()
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let binding = try #require(sema.bindings.callBindings.values.first {
            sema.symbols.symbol($0.chosenCallee)?.name == ctx.interner.intern("getOffset")
        })
        #expect(binding.substitutedTypeArguments.contains(sema.types.stringType))
    }

    @Test
    func argumentCannotWidenDispatchTypeParameter() throws {
        let ctx = makeContextFromSource("""
        open class GenericOffset<T> {
            fun Int.accept(value: T) {}
        }
        class DerivedOffset : GenericOffset<String>() {
            fun run(n: Int) { n.accept(9) }
        }
        """)
        try runToKIR(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test
    func cachedResolutionDistinguishesDispatchTypeArguments() throws {
        let ctx = makeContextFromSource("""
        class GenericOffset<T>(private val offset: T) {
            fun Int.getOffset(): T = offset
        }
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let function = try findKIRFunction(named: "getOffset", in: module, interner: ctx.interner)
        let owner = try #require(sema.symbols.memberExtensionOwnerSymbol(for: function.symbol))
        let signature = try #require(sema.symbols.functionSignature(for: function.symbol))
        let parameter = try #require(signature.typeParameterSymbols.first)
        let variable = try #require(sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)[parameter])
        let resolver = OverloadResolver()
        let cache = SemaCacheContext()
        resolver.cacheContext = cache
        for type in [sema.types.intType, sema.types.stringType, sema.types.intType] {
            let receiver = sema.types.make(.classType(ClassType(
                classSymbol: owner, args: [.invariant(type)], nullability: .nonNull
            )))
            let resolved = resolver.resolveCall(
                candidates: [function.symbol],
                call: CallExpr(
                    range: makeRange(start: 0, end: 1),
                    calleeName: ctx.interner.intern("getOffset"),
                    args: [],
                    dispatchReceiverTypes: [receiver]
                ),
                expectedType: nil,
                implicitReceiverType: sema.types.intType,
                ctx: sema
            )
            #expect(resolved.diagnostic == nil)
            #expect(resolved.chosenCallee == function.symbol)
            #expect(resolved.substitutedTypeArguments[variable] == type)
        }
        #expect(cache.callResolutionMisses == 2)
        #expect(cache.callResolutionHits == 1)
    }

}
