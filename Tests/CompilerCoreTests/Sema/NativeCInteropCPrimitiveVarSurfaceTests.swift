#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCPrimitiveVarSurfaceTests {
    @Test
    func testCPrimitiveVarClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected CPrimitiveVar surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
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

        let cPrimitiveVarSymbol = try cinteropSymbol("CPrimitiveVar")
        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cPrimitiveVarTypeSymbol = try cinteropSymbol("CPrimitiveVar", "Type")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let nativePtrType = try cinteropType("NativePtr")
        let cPrimitiveVarType = try cinteropType("CPrimitiveVar")
        let cPrimitiveVarTypeClassType = try cinteropType("CPrimitiveVar", "Type")
        let fqName = try #require(sema.symbols.symbol(cPrimitiveVarSymbol)?.fqName)
        let typeFQName = try #require(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(cPrimitiveVarSymbol)?.flags)
        let typeFlags = try #require(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.flags)

        #expect(sema.symbols.symbol(cPrimitiveVarSymbol)?.kind == .class)
        #expect(flags.contains(.sealedType))
        #expect(flags.contains(.abstractType))
        #expect(flags.contains(.openType))
        #expect(sema.symbols.propertyType(for: cPrimitiveVarSymbol) == cPrimitiveVarType)
        #expect(sema.symbols.directSupertypes(for: cPrimitiveVarSymbol) == [cVariableSymbol])
        #expect(sema.types.directNominalSupertypes(for: cPrimitiveVarSymbol) == [cVariableSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSymbol = try #require(constructors.first {
            guard let signature = sema.symbols.functionSignature(for: $0) else {
                return false
            }
            return signature.parameterTypes == [nativePtrType]
                && signature.returnType == cPrimitiveVarType
        })
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(sema.symbols.symbol(constructorSymbol)?.visibility == .protected)
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])

        #expect(sema.symbols.symbol(cPrimitiveVarTypeSymbol)?.kind == .class)
        #expect(typeFlags.contains(.openType))
        #expect(sema.symbols.propertyType(for: cPrimitiveVarTypeSymbol) == cPrimitiveVarTypeClassType)
        #expect(sema.symbols.directSupertypes(for: cPrimitiveVarTypeSymbol) == [cVariableTypeSymbol])
        #expect(sema.types.directNominalSupertypes(for: cPrimitiveVarTypeSymbol) == [cVariableTypeSymbol])

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try #require(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.intType] && $0.returnType == cPrimitiveVarTypeClassType
        })
        #expect(typeConstructorSignature.valueParameterHasDefaultValues == [false])
    }

    @Test
    func testCPrimitiveVarResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPrimitiveVar

        fun pass(value: CPrimitiveVar): CPrimitiveVar {
            return value
        }
        """)
        try runSema(ctx)

        #expect(
            !ctx.diagnostics.hasError,
            "Expected CPrimitiveVar to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
#endif
