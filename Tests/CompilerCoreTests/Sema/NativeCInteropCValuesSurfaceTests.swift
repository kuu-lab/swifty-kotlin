#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCValuesSurfaceTests {
    @Test
    func testCValuesClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CValues surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
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

        let cValuesSymbol = try cinteropSymbol("CValues")
        let cValuesRefSymbol = try cinteropSymbol("CValuesRef")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cVariableType = try cinteropType("CVariable")
        let autofreeScopeType = try cinteropType("AutofreeScope")
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: cValuesSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let cValuesType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try #require(sema.symbols.symbol(cValuesSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(cValuesSymbol)?.flags)

        #expect(sema.symbols.symbol(cValuesSymbol)?.kind == .class)
        #expect(flags.contains(.abstractType))
        #expect(sema.types.nominalTypeParameterVariances(for: cValuesSymbol) == [.invariant])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cVariableType])
        #expect(sema.symbols.propertyType(for: cValuesSymbol) == cValuesType)
        #expect(sema.symbols.directSupertypes(for: cValuesSymbol) == [cValuesRefSymbol])
        #expect(sema.types.directNominalSupertypes(for: cValuesSymbol) == [cValuesRefSymbol])
        #expect(
            sema.symbols.supertypeTypeArgs(for: cValuesSymbol, supertype: cValuesRefSymbol)
            == [.invariant(typeParameterType)]
        )
        #expect(
            sema.types.nominalSupertypeTypeArgs(for: cValuesSymbol, supertype: cValuesRefSymbol)
            == [.invariant(typeParameterType)]
        )

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == cValuesType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [])

        let align = try #require(sema.symbols.lookup(fqName: fqName + [interner.intern("align")]))
        #expect(sema.symbols.propertyType(for: align) == sema.types.intType)
        #expect(sema.symbols.symbol(align)?.flags.contains(.abstractType) == true)

        let size = try #require(sema.symbols.lookup(fqName: fqName + [interner.intern("size")]))
        #expect(sema.symbols.propertyType(for: size) == sema.types.intType)
        #expect(sema.symbols.symbol(size)?.flags.contains(.abstractType) == true)

        let getPointer = try #require(sema.symbols.lookupAll(fqName: fqName + [interner.intern("getPointer")])
            .compactMap { sema.symbols.functionSignature(for: $0) }
            .first {
                $0.receiverType == cValuesType &&
                    $0.parameterTypes == [autofreeScopeType] &&
                    $0.returnType == cPointerType
            })
        #expect(getPointer.typeParameterSymbols == [typeParameter])
        #expect(getPointer.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(getPointer.classTypeParameterCount == 1)

        let placeSymbol = try #require(sema.symbols.lookupAll(fqName: fqName + [interner.intern("place")])
            .first {
                guard let signature = sema.symbols.functionSignature(for: $0) else {
                    return false
                }
                return signature.receiverType == cValuesType &&
                    signature.parameterTypes == [cPointerType] &&
                    signature.returnType == cPointerType
            })
        let place = try #require(sema.symbols.functionSignature(for: placeSymbol))
        #expect(place.typeParameterSymbols == [typeParameter])
        #expect(place.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(place.classTypeParameterCount == 1)
        #expect(sema.symbols.symbol(placeSymbol)?.flags.contains(.abstractType) == true)
        #expect(
            sema.symbols.annotations(for: placeSymbol).contains {
                $0.annotationFQName == "kotlin.IgnorableReturnValue"
            },
            "CValues.place should carry @IgnorableReturnValue"
        )
    }

    @Test
    func testCValuesMembersResolveInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.AutofreeScope
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CValuesRef
        import kotlinx.cinterop.CVariable

        fun <T : CVariable> readMetadata(value: CValues<T>): Int {
            return value.align + value.size
        }

        fun <T : CVariable> copy(value: CValues<T>, scope: AutofreeScope, pointer: CPointer<T>): CPointer<T> {
            value.getPointer(scope)
            return value.place(pointer)
        }

        fun <T : CVariable> upcast(value: CValues<T>): CValuesRef<T> {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CValues members to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
