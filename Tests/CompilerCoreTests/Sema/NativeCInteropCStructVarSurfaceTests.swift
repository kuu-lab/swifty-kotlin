#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCStructVarSurfaceTests {
    @Test
    func testCStructVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CStructVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let cStructVarSymbol = try cinteropSymbol("CStructVar")
        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cStructVarTypeSymbol = try cinteropSymbol("CStructVar", "Type")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let nativePtrType = try cinteropType("NativePtr")
        let cStructVarType = try cinteropType("CStructVar")
        let cStructVarTypeClassType = try cinteropType("CStructVar", "Type")
        let fqName = try #require(sema.symbols.symbol(cStructVarSymbol)?.fqName)
        let typeFQName = try #require(sema.symbols.symbol(cStructVarTypeSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(cStructVarSymbol)?.flags)
        let typeFlags = try #require(sema.symbols.symbol(cStructVarTypeSymbol)?.flags)

        #expect(sema.symbols.symbol(cStructVarSymbol)?.kind == .class)
        #expect(flags.contains(.abstractType))
        #expect(flags.contains(.openType))
        #expect(sema.symbols.propertyType(for: cStructVarSymbol) == cStructVarType)
        #expect(sema.symbols.directSupertypes(for: cStructVarSymbol) == [cVariableSymbol])
        #expect(sema.types.directNominalSupertypes(for: cStructVarSymbol) == [cVariableSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cStructVarType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])

        #expect(sema.symbols.symbol(cStructVarTypeSymbol)?.kind == .class)
        #expect(typeFlags.contains(.openType))
        #expect(sema.symbols.propertyType(for: cStructVarTypeSymbol) == cStructVarTypeClassType)
        #expect(sema.symbols.directSupertypes(for: cStructVarTypeSymbol) == [cVariableTypeSymbol])
        #expect(sema.types.directNominalSupertypes(for: cStructVarTypeSymbol) == [cVariableTypeSymbol])

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try #require(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.longType, sema.types.intType]
                && $0.returnType == cStructVarTypeClassType
        })
        #expect(typeConstructorSignature.valueParameterHasDefaultValues == [false, false])
    }

    @Test
    func testCStructVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CStructVar

        fun pass(value: CStructVar): CStructVar {
            return value
        }
        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CStructVar to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
