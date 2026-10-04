#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct FutureConstructorSyntheticSurfaceTests {
    @Test
    func constructorMatchesKotlin2310ValueClassContract() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let concurrent = ["kotlin", "native", "concurrent"].map(ctx.interner.intern)
        let futureSymbol = try #require(
            sema.symbols.lookup(fqName: concurrent + [ctx.interner.intern("Future")])
        )
        let futureTypeParameter = try #require(sema.types.nominalTypeParameterSymbols(for: futureSymbol).first)
        let futureType = sema.types.make(.classType(ClassType(
            classSymbol: futureSymbol,
            args: [.invariant(sema.types.make(.typeParam(TypeParamType(
                symbol: futureTypeParameter,
                nullability: .nonNull
            ))))],
            nullability: .nonNull
        )))

        let futureInfo = try #require(sema.symbols.symbol(futureSymbol))
        #expect(futureInfo.kind == .class)
        #expect(futureInfo.flags.contains(.valueType))
        #expect(sema.symbols.valueClassUnderlyingType(for: futureSymbol) == sema.types.intType)

        let constructor = try #require(
            sema.symbols.lookupAll(
                fqName: concurrent + [ctx.interner.intern("Future"), ctx.interner.intern("<init>")]
            ).first { constructorSymbol in
                guard sema.symbols.symbol(constructorSymbol)?.kind == .constructor,
                      let signature = sema.symbols.functionSignature(for: constructorSymbol)
                else {
                    return false
                }
                return signature.parameterTypes == [sema.types.intType]
                    && signature.returnType == futureType
            }
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(constructorInfo.visibility == .internal)
        #expect(constructorInfo.flags.contains(.synthetic))
        #expect(sema.symbols.externalLinkName(for: constructor) == nil)
        #expect(
            sema.symbols.annotations(for: constructor).contains {
                $0.annotationFQName == "kotlin.PublishedApi"
            }
        )
    }
}
#endif
