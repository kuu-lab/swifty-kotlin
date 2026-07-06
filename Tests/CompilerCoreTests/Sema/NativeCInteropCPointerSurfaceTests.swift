#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerSurfaceTests {
    @Test
    func testCPointerClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointer surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cValuesRefSymbol = try cinteropSymbol("CValuesRef")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))
        let autofreeScopeType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("AutofreeScope"),
            args: [],
            nullability: .nonNull
        )))
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: cPointerSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.symbol(cPointerSymbol)?.kind == .class)
        #expect(sema.types.nominalTypeParameterVariances(for: cPointerSymbol) == [.invariant])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(sema.symbols.propertyType(for: cPointerSymbol) == cPointerType)
        #expect(sema.symbols.directSupertypes(for: cPointerSymbol) == [cValuesRefSymbol])
        #expect(sema.types.directNominalSupertypes(for: cPointerSymbol) == [cValuesRefSymbol])
        #expect(
            sema.symbols.supertypeTypeArgs(for: cPointerSymbol, supertype: cValuesRefSymbol)
                == [.invariant(typeParameterType)]
        )
        #expect(
            sema.types.nominalSupertypeTypeArgs(for: cPointerSymbol, supertype: cValuesRefSymbol)
                == [.invariant(typeParameterType)]
        )

        let fqName = try #require(sema.symbols.symbol(cPointerSymbol)?.fqName)
        let getPointer = try #require(sema.symbols.lookupAll(fqName: fqName + [interner.intern("getPointer")])
            .compactMap { sema.symbols.functionSignature(for: $0) }
            .first {
                $0.receiverType == cPointerType &&
                    $0.parameterTypes == [autofreeScopeType] &&
                    $0.returnType == cPointerType
            })
        #expect(getPointer.typeParameterSymbols == [typeParameter])
        #expect(getPointer.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(getPointer.classTypeParameterCount == 1)
    }

    @Test
    func testCPointerGetPointerResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer

        fun <T : CPointed> pass(value: CPointer<T>, scope: AutofreeScope): CPointer<T> {
            return value.getPointer(scope)
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointer.getPointer to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
