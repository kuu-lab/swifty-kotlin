#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKMutableProperty1SyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KMutableProperty1 surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKMutableProperty1SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kProperty1Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty1")]
        ))
        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let kMutableProperty1Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty1")]
        ))
        let function1Symbol = try #require(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function1")]
        ))

        let kMutableProperty1Info = try #require(sema.symbols.symbol(kMutableProperty1Symbol))
        #expect(kMutableProperty1Info.kind == .interface)
        #expect(kMutableProperty1Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty1Symbol)
        #expect(typeParams.count == 2)
        #expect(sema.types.nominalTypeParameterVariances(for: kMutableProperty1Symbol) == [.invariant, .invariant])

        let receiverTypeParam = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[1],
            nullability: .nonNull
        )))
        let supertypes = sema.symbols.directSupertypes(for: kMutableProperty1Symbol)
        #expect(supertypes.contains(kProperty1Symbol))
        #expect(supertypes.contains(kMutablePropertySymbol))
        #expect(supertypes.contains(function1Symbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kProperty1Symbol) == [.invariant(receiverTypeParam), .invariant(valueType)]
        )
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: kMutablePropertySymbol) == [.invariant(valueType)]
        )
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty1Symbol, supertype: function1Symbol) == [.out(valueType), .in(receiverTypeParam)]
        )

        let setSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty1"), interner.intern("set")]
        ))
        let setSignature = try #require(sema.symbols.functionSignature(for: setSymbol))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kMutableProperty1Symbol,
            args: [.invariant(receiverTypeParam), .invariant(valueType)],
            nullability: .nonNull
        )))
        #expect(setSignature.receiverType == receiverType)
        #expect(setSignature.parameterTypes == [receiverTypeParam, valueType])
        #expect(setSignature.returnType == sema.types.unitType)
        #expect(setSignature.typeParameterSymbols == typeParams)
        #expect(setSignature.classTypeParameterCount == 2)
    }

    @Test func testKMutableProperty1SetResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty1

        fun <T, V> write(property: KMutableProperty1<T, V>, receiver: T, value: V) {
            property.set(receiver, value)
        }
        """

        _ = try makeSema(source: source)
    }
}
#endif
