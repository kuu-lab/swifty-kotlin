#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKProperty0SyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KProperty0 surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKProperty0SurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let functionPackage = ["kotlin", "Function"].map { interner.intern($0) }

        let kPropertySymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty")]
        ))
        let kProperty0Symbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0")]
        ))
        let function0Symbol = try #require(sema.symbols.lookup(
            fqName: functionPackage + [interner.intern("Function0")]
        ))

        let kProperty0Info = try #require(sema.symbols.symbol(kProperty0Symbol))
        #expect(kProperty0Info.kind == .interface)
        #expect(kProperty0Info.flags.contains(.synthetic))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: kProperty0Symbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: kProperty0Symbol) == [.out])

        let valueType = sema.types.make(.typeParam(TypeParamType(symbol: typeParams[0], nullability: .nonNull)))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kProperty0Symbol,
            args: [.out(valueType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(kPropertySymbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: kPropertySymbol) == [.out(valueType)]
        )
        #expect(sema.symbols.directSupertypes(for: kProperty0Symbol).contains(function0Symbol))
        #expect(
            sema.symbols.supertypeTypeArgs(for: kProperty0Symbol, supertype: function0Symbol) == [.out(valueType)]
        )

        let getSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("get")]
        ))
        let getSignature = try #require(sema.symbols.functionSignature(for: getSymbol))
        #expect(getSignature.receiverType == receiverType)
        #expect(getSignature.parameterTypes == [])
        #expect(getSignature.returnType == valueType)
        #expect(getSignature.typeParameterSymbols == typeParams)
        #expect(getSignature.classTypeParameterCount == 1)

        let getDelegateSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("getDelegate")]
        ))
        let getDelegateSignature = try #require(sema.symbols.functionSignature(for: getDelegateSymbol))
        #expect(getDelegateSignature.receiverType == receiverType)
        #expect(getDelegateSignature.parameterTypes == [])
        #expect(getDelegateSignature.returnType == sema.types.nullableAnyType)
        #expect(getDelegateSignature.typeParameterSymbols == typeParams)
        #expect(getDelegateSignature.classTypeParameterCount == 1)

        let invokeSymbol = try #require(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KProperty0"), interner.intern("invoke")]
        ))
        let invokeSignature = try #require(sema.symbols.functionSignature(for: invokeSymbol))
        #expect(invokeSignature.receiverType == receiverType)
        #expect(invokeSignature.parameterTypes == [])
        #expect(invokeSignature.returnType == valueType)
        #expect(sema.symbols.symbol(invokeSymbol)?.flags.contains(.operatorFunction) == true)
        #expect(invokeSignature.typeParameterSymbols == typeParams)
        #expect(invokeSignature.classTypeParameterCount == 1)
    }

    @Test func testKProperty0MemberCallsResolveInSource() throws {
        let source = """
        import kotlin.reflect.KProperty0

        fun <V> read(property: KProperty0<V>): V {
            val first = property.get()
            val second = property.invoke()
            return first
        }

        fun <V> delegateOf(property: KProperty0<V>): Any? =
            property.getDelegate()
        """

        _ = try makeSema(source: source)
    }
}
#endif
