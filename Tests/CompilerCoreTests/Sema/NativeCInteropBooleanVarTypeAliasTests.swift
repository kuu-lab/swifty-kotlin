#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct NativeCInteropBooleanVarTypeAliasTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected BooleanVar typealias surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
        return try #require(found, "\(fqPath.joined(separator: ".")) must be registered")
    }

    @Test
    func testBooleanVarTypeAliasIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let aliasSymbol = try symbol(["kotlinx", "cinterop", "BooleanVar"], sema: sema, interner: interner)

        #expect(sema.symbols.symbol(aliasSymbol)?.kind == .typeAlias)
    }

    @Test
    func testBooleanVarUnderlyingTypeIsBooleanVarOfBoolean() throws {
        let (sema, interner) = try makeSema()
        let aliasSymbol = try symbol(["kotlinx", "cinterop", "BooleanVar"], sema: sema, interner: interner)
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let expectedUnderlying = sema.types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(sema.types.booleanType)],
            nullability: .nonNull
        )))

        #expect(sema.symbols.typeAliasUnderlyingType(for: aliasSymbol) == expectedUnderlying)
    }

    @Test
    func testBooleanVarOfSupportSymbolIsGeneric() throws {
        let (sema, interner) = try makeSema()
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: booleanVarOfSymbol)

        #expect(sema.symbols.symbol(booleanVarOfSymbol)?.kind == .class)
        #expect(typeParameters.count == 1)
        let typeParameter = try #require(typeParameters.first)
        #expect(sema.symbols.symbol(typeParameter)?.name == interner.intern("T"))
        #expect(sema.symbols.typeParameterUpperBounds(for: typeParameter) == [sema.types.booleanType])
    }

    @Test
    func testBooleanVarOfClassSurfaceMatchesNativeShape() throws {
        let (sema, interner) = try makeSema()
        let booleanVarOfSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf"], sema: sema, interner: interner)
        let cPrimitiveVarSymbol = try symbol(["kotlinx", "cinterop", "CPrimitiveVar"], sema: sema, interner: interner)
        let cVariableSymbol = try symbol(["kotlinx", "cinterop", "CVariable"], sema: sema, interner: interner)
        let cPointedSymbol = try symbol(["kotlinx", "cinterop", "CPointed"], sema: sema, interner: interner)
        let nativePtrSymbol = try symbol(["kotlinx", "cinterop", "NativePtr"], sema: sema, interner: interner)
        let booleanVarOfFQName = try #require(sema.symbols.symbol(booleanVarOfSymbol)?.fqName)
        let typeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: booleanVarOfSymbol).first)
        let typeParameterType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParameter,
            nullability: .nonNull
        )))
        let booleanVarOfType = sema.types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let nativePtrType = sema.types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))

        #expect(sema.symbols.directSupertypes(for: booleanVarOfSymbol) == [cPrimitiveVarSymbol])
        #expect(sema.symbols.directSupertypes(for: cPrimitiveVarSymbol) == [cVariableSymbol])
        #expect(sema.symbols.directSupertypes(for: cVariableSymbol) == [cPointedSymbol])

        let constructors = sema.symbols.lookupAll(fqName: booleanVarOfFQName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [nativePtrType] && $0.returnType == booleanVarOfType
        })
        #expect(constructorSignature.typeParameterSymbols == [typeParameter])
        #expect(constructorSignature.classTypeParameterCount == 1)

        let valueSymbol = try symbol(["kotlinx", "cinterop", "BooleanVarOf", "value"], sema: sema, interner: interner)
        #expect(sema.symbols.propertyType(for: valueSymbol) == typeParameterType)
    }

    @Test
    func testBooleanVarResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BooleanVar

        fun roundtrip(value: BooleanVar): BooleanVar {
            return value
        }
        """)
    }

    @Test
    func testBooleanVarOfValuePropertyResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BooleanVarOf

        fun readBoolean(value: BooleanVarOf<Boolean>): Boolean {
            return value.value
        }
        """)
    }
}
#endif
