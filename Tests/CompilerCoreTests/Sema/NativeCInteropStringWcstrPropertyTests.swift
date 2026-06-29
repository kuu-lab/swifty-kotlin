#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropStringWcstrPropertyTests {
    @Test func testStringWcstrPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected String.wcstr surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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
        let uShortVarSymbol = try cinteropSymbol("UShortVar")
        let uShortVarType = sema.types.make(.classType(ClassType(
            classSymbol: uShortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uShortVarType)],
            nullability: .nonNull
        )))
        let propertyFQName = cinteropPkg + [interner.intern("wcstr")]
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

    @Test func testStringWcstrPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.wcstr

        fun encode(value: String): Any {
            return value.wcstr
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected String.wcstr to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
