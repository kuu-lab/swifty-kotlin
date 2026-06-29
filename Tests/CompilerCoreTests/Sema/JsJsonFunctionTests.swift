#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JsJsonFunctionTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testJsonInterfaceAndFactoryFunctionAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let kotlinJsFQName = ["kotlin", "js"].map { interner.intern($0) }
        let kotlinJsPackage = try #require(
            sema.symbols.lookup(fqName: kotlinJsFQName),
            "Expected kotlin.js package to be registered"
        )

        let jsonFQName = kotlinJsFQName + [interner.intern("Json")]
        let jsonSymbol = try #require(
            sema.symbols.lookup(fqName: jsonFQName),
            "Expected kotlin.js.Json to be registered"
        )
        let jsonInfo = try #require(sema.symbols.symbol(jsonSymbol))
        #expect(jsonInfo.kind == .interface)
        #expect(jsonInfo.visibility == .public)
        #expect(jsonInfo.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: jsonSymbol) == kotlinJsPackage)

        let jsonType = sema.types.make(.classType(ClassType(
            classSymbol: jsonSymbol,
            args: [],
            nullability: .nonNull
        )))
        #expect(sema.symbols.propertyType(for: jsonSymbol) == jsonType)

        let pairFQName = [interner.intern("kotlin"), interner.intern("Pair")]
        let pairSymbol = try #require(
            sema.symbols.lookup(fqName: pairFQName),
            "Expected kotlin.Pair to be available for json(vararg pairs)"
        )
        let pairStringNullableAnyType = sema.types.make(.classType(ClassType(
            classSymbol: pairSymbol,
            args: [
                .out(sema.types.stringType),
                .out(sema.types.nullableAnyType),
            ],
            nullability: .nonNull
        )))

        let jsonFunctionFQName = kotlinJsFQName + [interner.intern("json")]
        let jsonFunctionSymbol = try #require(
            sema.symbols.lookupAll(fqName: jsonFunctionFQName).first { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes == [pairStringNullableAnyType]
                    && signature.returnType == jsonType
                    && signature.valueParameterIsVararg == [true]
            },
            "Expected kotlin.js.json(vararg pairs: Pair<String, Any?>): Json"
        )
        let jsonFunctionInfo = try #require(sema.symbols.symbol(jsonFunctionSymbol))
        #expect(jsonFunctionInfo.kind == .function)
        #expect(jsonFunctionInfo.visibility == .public)
        #expect(jsonFunctionInfo.flags.contains(.synthetic))
        #expect(sema.symbols.parentSymbol(for: jsonFunctionSymbol) == kotlinJsPackage)
        #expect(sema.symbols.externalLinkName(for: jsonFunctionSymbol) == nil)

        let signature = try #require(sema.symbols.functionSignature(for: jsonFunctionSymbol))
        #expect(signature.parameterTypes == [pairStringNullableAnyType])
        #expect(signature.returnType == jsonType)
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [true])

        let pairsParameter = try #require(signature.valueParameterSymbols.first)
        #expect(sema.symbols.symbol(pairsParameter)?.name == interner.intern("pairs"))
        #expect(sema.symbols.parentSymbol(for: pairsParameter) == jsonFunctionSymbol)
        #expect(sema.symbols.propertyType(for: pairsParameter) == pairStringNullableAnyType)
    }
}
#endif
