#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropByteVarTypeAliasTests {
    @Test
    func testByteVarTypeAliasSurface() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !(ctx.diagnostics.hasError),
            "Expected ByteVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func symbol(_ fqPath: [String]) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
            return try requireTestValue(found, "\(fqPath.joined(separator: ".")) must be registered")
        }

        let aliasSymbol = try symbol(["kotlinx", "cinterop", "ByteVar"])
        let byteVarOfSymbol = try symbol(["kotlinx", "cinterop", "ByteVarOf"])
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(sema.types.intType)],
            nullability: .nonNull
        )))
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: byteVarOfSymbol)

        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
        #expect(sema.symbols.symbol(byteVarOfSymbol)?.kind == .class)
        #expect(typeParameters.count == 1)
        let typeParameter = try #require(typeParameters.first)
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.intType])
    }

    @Test
    func testByteVarOfClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        func cinteropSymbol(_ name: String) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: ["kotlinx", "cinterop", name].map { interner.intern($0) })
            return try requireTestValue(found, "kotlinx.cinterop.\(name) must be registered")
        }

        let byteVarOfSymbol = try cinteropSymbol("ByteVarOf")
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: byteVarOfSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let byteVarOfType = sema.types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol("NativePtr"),
            args: [],
            nullability: .nonNull
        )))

        #expect(sema.symbols.directSupertypes(for: byteVarOfSymbol) == [try cinteropSymbol("CPrimitiveVar")])
        #expect(sema.symbols.directSupertypes(for: try cinteropSymbol("CPrimitiveVar")) == [try cinteropSymbol("CVariable")])
        #expect(sema.symbols.directSupertypes(for: try cinteropSymbol("CVariable")) == [try cinteropSymbol("CPointed")])

        let fqName = try #require(sema.symbols.symbol(byteVarOfSymbol)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == byteVarOfType
        })
        #expect(constructorSignature.typeParameterSymbols == [typeParameter])
        #expect(constructorSignature.classTypeParameterCount == 1)

        let valueSymbol = try #require(
            sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "ByteVarOf", "value"].map { interner.intern($0) })
        )
        #expect(sema.symbols.propertyType(for: valueSymbol) == typeParameterType)
    }

    @Test
    func testByteVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVar

        fun roundtrip(value: ByteVar): ByteVar {
            return value
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected ByteVar typealias to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testByteVarOfValuePropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.ByteVarOf

        fun readByte(value: ByteVarOf<Byte>): Byte {
            return value.value
        }
        """)
        try runSema(ctx)

        #expect(
            !(ctx.diagnostics.hasError),
            "Expected ByteVarOf.value to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
