#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropDeferScopeSurfaceTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected DeferScope surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        return (try #require(ctx.sema), ctx.interner)
    }

    private func cinteropSymbol(
        _ path: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try #require(sema.symbols.lookup(fqName: (["kotlinx", "cinterop"] + path).map { interner.intern($0) }), "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
    }

    private func cinteropSymbol(
        _ path: String...,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        try cinteropSymbol(path, sema: sema, interner: interner, file: file, line: line)
    }

    private func cinteropType(
        _ path: String...,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        sema.types.make(.classType(ClassType(
            classSymbol: try cinteropSymbol(path, sema: sema, interner: interner, file: file, line: line),
            args: [],
            nullability: .nonNull
        )))
    }

    @Test func testDeferScopeClassSurfaceMatchesNativeShape() throws {
        let (sema, interner) = try makeSema()

        let deferScopeSymbol = try cinteropSymbol("DeferScope", sema: sema, interner: interner)
        let deferScopeType = try cinteropType("DeferScope", sema: sema, interner: interner)
        let fqName = try #require(sema.symbols.symbol(deferScopeSymbol)?.fqName)
        let flags = try #require(sema.symbols.symbol(deferScopeSymbol)?.flags)

        #expect(sema.symbols.symbol(deferScopeSymbol)?.kind == .class)
        #expect(flags.contains(.openType))
        #expect(sema.symbols.propertyType(for: deferScopeSymbol) == deferScopeType)
        #expect(sema.symbols.directSupertypes(for: deferScopeSymbol) == [])
        #expect(sema.types.directNominalSupertypes(for: deferScopeSymbol) == [])

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try #require(constructors.compactMap {
            sema.symbols.functionSignature(for: $0)
        }.first {
            $0.parameterTypes.isEmpty && $0.returnType == deferScopeType
        })
        #expect(constructorSignature.valueParameterHasDefaultValues == [])
    }

    @Test func testDeferScopeDeferMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let deferScopeSymbol = try cinteropSymbol("DeferScope", sema: sema, interner: interner)
        let deferScopeType = try cinteropType("DeferScope", sema: sema, interner: interner)
        let fqName = try #require(sema.symbols.symbol(deferScopeSymbol)?.fqName)
        let blockType = sema.types.make(.functionType(FunctionType(
            params: [],
            returnType: sema.types.unitType
        )))
        let deferMembers = sema.symbols.lookupAll(fqName: fqName + [interner.intern("defer")])
        let deferSymbol = try #require(deferMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == deferScopeType
                && signature.parameterTypes == [blockType]
                && signature.returnType == sema.types.unitType
        })
        let signature = try #require(sema.symbols.functionSignature(for: deferSymbol))

        #expect(sema.symbols.symbol(deferSymbol)?.flags.isSuperset(of: [.synthetic, .inlineFunction]) == true)
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
        let blockParameter = try #require(signature.valueParameterSymbols.first)
        #expect(sema.symbols.symbol(blockParameter)?.name == interner.intern("block"))
        #expect(sema.symbols.propertyType(for: blockParameter) == blockType)
    }

    @Test func testDeferScopeResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.DeferScope

        fun makeScope(): DeferScope {
            return DeferScope()
        }

        fun register(scope: DeferScope) {
            scope.defer {
            }
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected DeferScope constructor and defer member to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
