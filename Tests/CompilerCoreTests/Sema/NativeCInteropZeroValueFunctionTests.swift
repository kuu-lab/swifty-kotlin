#if canImport(Testing)
@testable import CompilerCore
import Testing

// STDLIB-CINTEROP-FN-047: kotlinx.cinterop.zeroValue<T>() stub registration
@Suite
struct NativeCInteropZeroValueFunctionTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected zeroValue surface to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testZeroValueIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        let zeroValueSymbol = try #require(
            sema.symbols.lookupAll(fqName: cinteropPkg + [interner.intern("zeroValue")]).first,
            "Expected kotlinx.cinterop.zeroValue to be registered"
        )
        let info = try #require(sema.symbols.symbol(zeroValueSymbol))
        #expect(info.kind == .function)
        #expect(info.flags.contains(.synthetic))
        #expect(info.flags.contains(.inlineFunction))

        let sig = try #require(sema.symbols.functionSignature(for: zeroValueSymbol))
        #expect(sig.receiverType == nil)
        #expect(sig.parameterTypes.isEmpty)
        #expect(sig.reifiedTypeParameterIndices == [0])
        #expect(sig.typeParameterSymbols.count == 1)

        let typeParameter = try #require(sig.typeParameterSymbols.first)
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        let typeParameterFlags = try #require(sema.symbols.symbol(typeParameter)?.flags)
        #expect(typeParameterFlags.contains(.reifiedTypeParameter))

        let cVariableSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CVariable")]),
            "Expected kotlinx.cinterop.CVariable to be registered"
        )
        let cVariableType = sema.types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])

        let cValueSymbol = try #require(
            sema.symbols.lookup(fqName: cinteropPkg + [interner.intern("CValue")]),
            "Expected kotlinx.cinterop.CValue to be registered"
        )
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let expectedReturnType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        #expect(sig.returnType == expectedReturnType)
        #expect(sig.typeParameterUpperBoundsList == [[cVariableType]])
    }

    @Test
    func testZeroValueResolvesInSource() throws {
        let source = """
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.zeroValue

        @ExperimentalForeignApi
        fun <T : CVariable> makeZero(): CValue<T> = zeroValue()
        """
        let (_, _) = try makeSema(source: source)
    }
}
#endif
