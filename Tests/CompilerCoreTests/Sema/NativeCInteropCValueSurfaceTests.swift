#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCValueSurfaceTests {
    @Test
    func testCValueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CValue surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let cValueSymbol = try cinteropSymbol("CValue")
        let cValuesSymbol = try cinteropSymbol("CValues")
        let cVariableType = try cinteropType("CVariable")
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: cValueSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cValueType = sema.types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try #require(sema.symbols.symbol(cValueSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(cValueSymbol)?.flags)

        #expect(sema.symbols.symbol(cValueSymbol)?.kind == .class)
        #expect(flags.contains(.abstractType))
        #expect(sema.types.nominalTypeParameterVariances(for: cValueSymbol) == [.invariant])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])
        #expect(sema.symbols.propertyType(for: cValueSymbol) == cValueType)
        #expect(sema.symbols.directSupertypes(for: cValueSymbol) == [cValuesSymbol])
        #expect(sema.types.directNominalSupertypes(for: cValueSymbol) == [cValuesSymbol])
        #expect(
            sema.symbols.supertypeTypeArgs(for: cValueSymbol, supertype: cValuesSymbol)
            == [.invariant(typeParameterType)]
        )
        #expect(
            sema.types.nominalSupertypeTypeArgs(for: cValueSymbol, supertype: cValuesSymbol)
            == [.invariant(typeParameterType)]
        )

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == cValueType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [])
    }

    @Test
    func testCValueResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CVariable

        fun <T : CVariable> upcast(value: CValue<T>): CValues<T> {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CValue to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
