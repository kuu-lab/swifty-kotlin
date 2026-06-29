#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropStringCstrPropertyTests {
    @Test func testStringCstrPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected String.cstr surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cValuesSymbol = try cinteropSymbol("CValues")
        let byteVarAlias = try cinteropSymbol("ByteVar")
        let byteVarType = try #require(sema.symbols.typeAliasUnderlyingType(for: byteVarAlias))
        let expectedPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        let propertyFQName = cinteropPkg + [interner.intern("cstr")]
        let propertySymbol = try #require(sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) == sema.types.stringType
        })
        let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try #require(sema.symbols.functionSignature(for: getterSymbol))
        let flags = try #require(sema.symbols.symbol(propertySymbol)?.flags)

        #expect(flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: propertySymbol) == sema.symbols.lookup(fqName: cinteropPkg))
        #expect(sema.symbols.propertyType(for: propertySymbol) == expectedPropertyType)
        #expect(getterSignature.receiverType == sema.types.stringType)
        #expect(getterSignature.parameterTypes == [])
        #expect(getterSignature.returnType == expectedPropertyType)
        #expect(sema.symbols.parentSymbol(for: getterSymbol) == propertySymbol)
        #expect(sema.symbols.accessorOwnerProperty(for: getterSymbol) == propertySymbol)
    }

    @Test func testStringCstrPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar
        import kotlinx.cinterop.CValues
        import kotlinx.cinterop.cstr

        fun encode(value: String): CValues<ByteVar> {
            return value.cstr
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected String.cstr to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
