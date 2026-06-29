#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropStableRefSurfaceTests {
    @Test
    func testStableRefValueClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected StableRef surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }

        let stableRefSymbol = try cinteropSymbol("StableRef")
        let cPointedSymbol = try cinteropSymbol("CPointed")
        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cOpaquePointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: stableRefSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let stableRefType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let fqName = try #require(sema.symbols.symbol(stableRefSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(stableRefSymbol)?.flags)

        #expect(sema.symbols.symbol(stableRefSymbol)?.kind == .class)
        #expect(flags.contains(.valueType))
        #expect(sema.types.nominalTypeParameterVariances(for: stableRefSymbol) == [.out])
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.anyType])
        #expect(sema.symbols.propertyType(for: stableRefSymbol) == stableRefType)
        #expect(sema.symbols.valueClassUnderlyingType(for: stableRefSymbol) == cOpaquePointerType)

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [cOpaquePointerType] && $0.returnType == stableRefType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])
    }

    @Test
    func testStableRefMembersAndCompanionCreateAreRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected StableRef members to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let stableRefFQName = ["kotlinx", "cinterop", "StableRef"].map { interner.intern($0) }
        let stableRefSymbol = try #require(sema.symbols.lookup(fqName: stableRefFQName))
        let cPointedSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "CPointed"].map { interner.intern($0) })
        )
        let cPointerSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "CPointer"].map { interner.intern($0) })
        )
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: stableRefSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let stableRefType = sema.types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(typeParameterType)],
            nullability: .nonNull
        )))
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let cOpaquePointerType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        let memberExpectations: [(name: String, returnType: TypeID)] = [
            ("asCPointer", cOpaquePointerType),
            ("dispose", sema.types.unitType),
            ("get", typeParameterType),
        ]
        for expectation in memberExpectations {
            let member = try #require(sema.symbols.lookupAll(fqName: stableRefFQName + [interner.intern(expectation.name)])
                .first { symbol in
                    guard let signature = sema.symbols.functionSignature(for: symbol) else {
                        return false
                    }
                    return signature.receiverType == stableRefType
                        && signature.parameterTypes.isEmpty
                        && signature.returnType == expectation.returnType
                        && signature.typeParameterSymbols == [typeParameter]
                        && signature.classTypeParameterCount == 1
                })
            #expect(sema.symbols.symbol(member)?.flags.contains(.synthetic) == true)
        }

        let companionSymbol = try #require(sema.symbols.lookup(fqName: stableRefFQName + [interner.intern("Companion")]))
        let companionType = try #require(sema.symbols.propertyType(for: companionSymbol))
        let createSymbol = try #require(sema.symbols.lookupAll(
            fqName: stableRefFQName + [interner.intern("Companion"), interner.intern("create")]
        ).first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol),
                  let createTypeParameter = signature.typeParameterSymbols.first
            else {
                return false
            }
            let createTypeParameterType = sema.types.make(.typeParam(TypeParamType(
                symbol: createTypeParameter,
                nullability: .nonNull
            )))
            let expectedReturnType = sema.types.make(.classType(ClassType(
                classSymbol: stableRefSymbol,
                args: [.out(createTypeParameterType)],
                nullability: .nonNull
            )))
            return signature.receiverType == companionType
                && signature.parameterTypes == [createTypeParameterType]
                && signature.returnType == expectedReturnType
                && signature.typeParameterUpperBoundsList == [[sema.types.anyType]]
        })
        #expect(sema.symbols.symbol(createSymbol)?.flags.isSuperset(of: [.synthetic, .static]) == true)
    }

    @Test
    func testStableRefResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.COpaquePointer
        import kotlinx.cinterop.StableRef

        fun <T : Any> create(value: T): StableRef<T> {
            return StableRef.create(value)
        }

        fun <T : Any> pointer(ref: StableRef<T>): COpaquePointer {
            val value: T = ref.get()
            ref.dispose()
            return ref.asCPointer()
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected StableRef to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
