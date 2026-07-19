#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointedSurfaceTests {
    @Test
    func testCPointedClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointed surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
            let found = sema.symbols.lookup(
                fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) }
            )
            return try requireTestValue(
                found,
                "kotlinx.cinterop.\(name) must be registered"
            )
        }
        func cinteropType(_ name: String) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(name),
                args: [],
                nullability: .nonNull
            )))
        }

        let cPointedSymbol = try cinteropSymbol("CPointed")
        let cPointedType = try cinteropType("CPointed")
        let nativePointedSymbol = try cinteropSymbol("NativePointed")
        let nativePtrType = try cinteropType("NativePtr")
        let cVariableType = try cinteropType("CVariable")
        let fqName = try #require(sema.symbols.symbol(cPointedSymbol)?.fqName)

        func readSignature(named name: String, parameters: [TypeID]) throws -> FunctionSignature {
            let candidates = sema.symbols.lookupAll(
                fqName: fqName + [interner.intern(name)]
            )
            for candidate in candidates {
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.receiverType == cPointedType,
                      signature.parameterTypes == parameters,
                      signature.typeParameterSymbols.count == 1
                else {
                    continue
                }
                return signature
            }
            return try requireTestValue(
                nil as FunctionSignature?,
                "Expected CPointed.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })"
            )
        }

        #expect(sema.symbols.symbol(cPointedSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(cPointedSymbol)?.flags.contains(.abstractType) == true)
        #expect(sema.symbols.propertyType(for: cPointedSymbol) == cPointedType)
        #expect(sema.symbols.directSupertypes(for: cPointedSymbol) == [nativePointedSymbol])
        #expect(sema.types.directNominalSupertypes(for: cPointedSymbol) == [nativePointedSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cPointedType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])

        let rawPtrSymbol = try #require(sema.symbols.lookup(fqName: fqName + [interner.intern("rawPtr")]))
        #expect(sema.symbols.symbol(rawPtrSymbol)?.kind == .property)
        #expect(sema.symbols.symbol(rawPtrSymbol)?.flags.contains(.mutable) == true)
        #expect(sema.symbols.propertyType(for: rawPtrSymbol) == nativePtrType)

        let readValue = try readSignature(named: "readValue", parameters: [sema.types.longType, sema.types.intType])
        let readValueTypeParameter = try #require(readValue.typeParameterSymbols.first)
        let readValueTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: readValueTypeParameter,
            nullability: .nonNull
        )))
        #expect(sema.symbols.typeParameterUpperBounds(for: readValueTypeParameter) == [cVariableType])
        #expect(readValue.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(readValue.returnType == sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CValue"),
            args: [.invariant(readValueTypeParameterType)],
            nullability: .nonNull
        ))))

        let readValues = try readSignature(named: "readValues", parameters: [sema.types.intType, sema.types.intType])
        let readValuesTypeParameter = try #require(readValues.typeParameterSymbols.first)
        let readValuesTypeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: readValuesTypeParameter,
            nullability: .nonNull
        )))
        #expect(sema.symbols.typeParameterUpperBounds(for: readValuesTypeParameter) == [cVariableType])
        #expect(readValues.typeParameterUpperBoundsList == [[cVariableType]])
        #expect(readValues.returnType == sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CValues"),
            args: [.invariant(readValuesTypeParameterType)],
            nullability: .nonNull
        ))))
    }

    @Test
    func testCPointedMembersResolveInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CValue
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.NativePtr

        fun getRawPtr(value: CPointed): NativePtr {
            return value.rawPtr
        }

        fun <T : CVariable> readOne(value: CPointed): CValue<T> {
            return value.readValue<T>(8L, 4)
        }

        fun <T : CVariable> readMany(value: CPointed): CValues<T> {
            return value.readValues<T>(2, 4)
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected CPointed members to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
