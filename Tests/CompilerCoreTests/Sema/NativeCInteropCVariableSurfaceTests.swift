#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropCVariableSurfaceTests {
    @Test
    func testCVariableClassSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CVariable surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
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

        let cVariableSymbol = try cinteropSymbol("CVariable")
        let cVariableTypeSymbol = try cinteropSymbol("CVariable", "Type")
        let cPointedSymbol = try cinteropSymbol("CPointed")
        let nativePtrType = try cinteropType("NativePtr")
        let cVariableType = try cinteropType("CVariable")
        let cVariableTypeClassType = try cinteropType("CVariable", "Type")
        let fqName = try #require(sema.symbols.symbol(cVariableSymbol)?.fqName)
        let typeFQName = try #require(sema.symbols.symbol(cVariableTypeSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(cVariableSymbol)?.flags)
        let typeFlags = try #require(sema.symbols.symbol(cVariableTypeSymbol)?.flags)

        #expect(sema.symbols.symbol(cVariableSymbol)?.kind == .class)
        #expect(flags.contains(.abstractType))
        #expect(sema.symbols.propertyType(for: cVariableSymbol) == cVariableType)
        #expect(sema.symbols.directSupertypes(for: cVariableSymbol) == [cPointedSymbol])
        #expect(sema.types.directNominalSupertypes(for: cVariableSymbol) == [cPointedSymbol])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == cVariableType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [false])

        #expect(sema.symbols.symbol(cVariableTypeSymbol)?.kind == .class)
        #expect(typeFlags.contains(.openType))
        #expect(sema.symbols.propertyType(for: cVariableTypeSymbol) == cVariableTypeClassType)
        #expect(sema.symbols.directSupertypes(for: cVariableTypeSymbol) == [])
        #expect(sema.types.directNominalSupertypes(for: cVariableTypeSymbol) == [])
        #expect(
            sema.symbols.annotations(for: cVariableTypeSymbol).contains {
                $0.annotationFQName == "kotlin.Deprecated" &&
                    $0.arguments == ["message = \"Use sizeOf<T>() or alignOf<T>() instead.\""]
            }
        )

        let typeConstructors = sema.symbols.lookupAll(fqName: typeFQName + [interner.intern("<init>")])
        let typeConstructorSignature = try #require(typeConstructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes == [sema.types.longType, sema.types.intType]
                && $0.returnType == cVariableTypeClassType
        })
        #expect(typeConstructorSignature.valueParameterHasDefaultValues == [false, false])

        let sizeSymbol = try #require(sema.symbols.lookup(fqName: typeFQName + [interner.intern("size")]))
        #expect(sema.symbols.propertyType(for: sizeSymbol) == sema.types.longType)
        let alignSymbol = try #require(sema.symbols.lookup(fqName: typeFQName + [interner.intern("align")]))
        #expect(sema.symbols.propertyType(for: alignSymbol) == sema.types.intType)
    }

    @Test
    func testCVariableResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.CPointed
        import kotlinx.cinterop.CVariable
        import kotlinx.cinterop.NativePtr

        fun upcast(value: CVariable): CPointed {
            return value
        }

        fun raw(value: CVariable): NativePtr {
            return value.rawPtr
        }

        """)
        try runSema(ctx)

        #expect(!(
            ctx.diagnostics.hasError
        ), "Expected CVariable members to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
