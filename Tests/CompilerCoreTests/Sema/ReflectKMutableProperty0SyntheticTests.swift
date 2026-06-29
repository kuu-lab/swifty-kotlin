#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKMutableProperty0SyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KMutableProperty0 surface to resolve cleanly, got: \(diagnostics)"))
            result = try (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKMutableProperty0SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kProperty0Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0")]
        ))
        let kMutablePropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty")]
        ))
        let kMutableProperty0Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty0")]
        ))
        let function0Symbol = try #require(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function0")]
        ))

        let kMutableProperty0Info = try #require(sema.symbols.symbol(kMutableProperty0Symbol))
        #expect(kMutableProperty0Info.kind == .interface)
        #expect(kMutableProperty0Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kMutableProperty0Symbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: kMutableProperty0Symbol) == [.invariant])

        let valueType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let supertypes = sema.symbols.directSupertypes(for: kMutableProperty0Symbol)
        #expect(supertypes.contains(kProperty0Symbol))
        #expect(supertypes.contains(kMutablePropertySymbol))
        #expect(supertypes.contains(function0Symbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: kProperty0Symbol) == [.invariant(valueType)]
        )
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: kMutablePropertySymbol) == [.invariant(valueType)]
        )
        #expect(
            sema.symbols.supertypeTypeArgs(for: kMutableProperty0Symbol, supertype: function0Symbol) == [.out(valueType)]
        )

        let setSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KMutableProperty0"), interner.intern("set")]
        ))
        let setSignature = try #require(sema.symbols.functionSignature(for: setSymbol))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kMutableProperty0Symbol,
            args: [.invariant(valueType)],
            nullability: .nonNull
        )))
        #expect(setSignature.receiverType == receiverType)
        #expect(setSignature.parameterTypes == [valueType])
        #expect(setSignature.returnType == sema.types.unitType)
        #expect(setSignature.typeParameterSymbols == typeParams)
        #expect(setSignature.classTypeParameterCount == 1)
    }

    @Test func testKMutableProperty0SetResolvesInSource() throws {
        let source = """
        import kotlin.reflect.KMutableProperty0

        fun <V> write(property: KMutableProperty0<V>, value: V) {
            property.set(value)
        }
        """

        _ = try makeSema(source: source)
    }
}
#endif
