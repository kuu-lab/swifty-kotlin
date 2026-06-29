#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPointerPointedPropertyTests {
    @Test func testCPointerPointedPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.pointed surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + [interner.intern(name)])
            return try #require(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let cPointerSymbol = try cinteropSymbol("CPointer")
        let cPointedType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("CPointed"),
            args: [],
            nullability: .nonNull
        )))

        let pointedFQName = cinteropPkg + [interner.intern("pointed")]
        let propertySymbol = try #require(
            sema.symbols.lookupAll(fqName: pointedFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "kotlinx.cinterop.CPointer<T>.pointed must be registered"
        )
        let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try #require(sema.symbols.functionSignature(for: getterSymbol))
        let typeParameter = try #require(getterSignature.typeParameterSymbols.first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.propertyType(for: propertySymbol) == typeParameterType)
        #expect(sema.symbols.extensionPropertyReceiverType(for: propertySymbol) == receiverType)
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [cPointedType])
        #expect(getterSignature.receiverType == receiverType)
        #expect(getterSignature.parameterTypes == [])
        #expect(getterSignature.returnType == typeParameterType)
        #expect(getterSignature.typeParameterUpperBoundsList == [[cPointedType]])
        #expect(getterSignature.classTypeParameterCount == 0)
    }

    @Test func testCPointerPointedPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CPointer
        import kotlinx.cinterop.pointed

        fun <T : CPointed> load(value: CPointer<T>): T {
            return value.pointed
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected CPointer.pointed to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
