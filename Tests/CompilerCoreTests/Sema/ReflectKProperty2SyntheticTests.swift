#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKProperty2SyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KProperty2 surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKProperty2SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kPropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kProperty2Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2")]
        ))
        let function2Symbol = try #require(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function2")]
        ))

        let kProperty2Info = try #require(sema.symbols.symbol(kProperty2Symbol))
        #expect(kProperty2Info.kind == .interface)
        // KSP-682: KProperty2 is now bundled Kotlin source, not a synthetic stub.
        #expect(!kProperty2Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty2Symbol)
        #expect(typeParams.count == 3)
        #expect(sema.types.nominalTypeParameterVariances(for: kProperty2Symbol) == [.invariant, .invariant, .out])

        let dType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let eType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        let vType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[2], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty2Symbol,
            args: [.invariant(dType), .invariant(eType), .invariant(vType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.directSupertypes(for: kProperty2Symbol).contains(kPropertySymbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kProperty2Symbol, supertype: kPropertySymbol) == [.invariant(vType)]
        )
        #expect(sema.symbols.directSupertypes(for: kProperty2Symbol).contains(function2Symbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kProperty2Symbol, supertype: function2Symbol) == [.out(vType), .in(dType), .in(eType)]
        )

        let getSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("get")]
        ))
        let getSignature = try #require(sema.symbols.functionSignature(for: getSymbol))
        #expect(getSignature.receiverType == receiverType)
        #expect(getSignature.parameterTypes == [dType, eType])
        #expect(getSignature.returnType == vType)
        #expect(getSignature.typeParameterSymbols == typeParams)
        #expect(getSignature.classTypeParameterCount == 3)

        let getDelegateSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("getDelegate")]
        ))
        let getDelegateSignature = try #require(sema.symbols.functionSignature(for: getDelegateSymbol))
        #expect(getDelegateSignature.receiverType == receiverType)
        #expect(getDelegateSignature.parameterTypes == [dType, eType])
        #expect(getDelegateSignature.returnType == sema.types.nullableAnyType)
        #expect(getDelegateSignature.typeParameterSymbols == typeParams)
        #expect(getDelegateSignature.classTypeParameterCount == 3)

        let invokeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2"), interner.intern("invoke")]
        ))
        let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
        #expect(invokeSignature.receiverType == receiverType)
        #expect(invokeSignature.parameterTypes == [dType, eType])
        #expect(invokeSignature.returnType == vType)
        #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
        #expect(invokeSignature.typeParameterSymbols == typeParams)
        #expect(invokeSignature.classTypeParameterCount == 3)
    }

    @Test func testKProperty2MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KProperty2

        fun <D, E, V> read(property: KProperty2<D, E, V>, receiver1: D, receiver2: E): V {
            val first = property.get(receiver1, receiver2)
            val second = property.invoke(receiver1, receiver2)
            return first
        }

        fun <D, E, V> delegateOf(property: KProperty2<D, E, V>, receiver1: D, receiver2: E): Any? =
            property.getDelegate(receiver1, receiver2)
        """

        _ = try makeSema(source: source)
    }

    @Test func testKMutableProperty2SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kProperty2Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty2")]
        ))
        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let kMutableProperty2Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty2")]
        ))

        let kMutableProperty2Info = try #require(sema.symbols.symbol(kMutableProperty2Symbol))
        #expect(kMutableProperty2Info.kind == .interface)
        // KSP-682: KMutableProperty2 is now bundled Kotlin source, not a synthetic stub.
        #expect(!kMutableProperty2Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty2Symbol)
        #expect(typeParams.count == 3)
        #expect(sema.types.nominalTypeParameterVariances(for: kMutableProperty2Symbol) == [.invariant, .invariant, .invariant])

        let dType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let eType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[1], nullability: .nonNull)))
        let vType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[2], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kMutableProperty2Symbol,
            args: [.invariant(dType), .invariant(eType), .invariant(vType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.directSupertypes(for: kMutableProperty2Symbol).contains(kProperty2Symbol))
        #expect(sema.symbols.directSupertypes(for: kMutableProperty2Symbol).contains(kMutablePropertySymbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty2Symbol, supertype: kProperty2Symbol) == [.invariant(dType), .invariant(eType), .invariant(vType)]
        )
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty2Symbol, supertype: kMutablePropertySymbol) == [.invariant(vType)]
        )

        let setSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty2"), interner.intern("set")]
        ))
        let setSignature = try #require(sema.symbols.functionSignature(for: setSymbol))
        #expect(setSignature.receiverType == receiverType)
        #expect(setSignature.parameterTypes == [dType, eType, vType])
        #expect(setSignature.returnType == sema.types.unitType)
        #expect(setSignature.typeParameterSymbols == typeParams)
        #expect(setSignature.classTypeParameterCount == 3)
    }

    @Test func testKMutableProperty2MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty2

        fun <D, E, V> write(property: KMutableProperty2<D, E, V>, receiver1: D, receiver2: E, value: V): V {
            property.set(receiver1, receiver2, value)
            val readBack = property.get(receiver1, receiver2)
            val invoked = property(receiver1, receiver2)
            return readBack
        }
        """

        _ = try makeSema(source: source)
    }
}
#endif
