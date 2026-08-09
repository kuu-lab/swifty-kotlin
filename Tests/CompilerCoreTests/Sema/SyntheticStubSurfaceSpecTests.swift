#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SyntheticStubSurfaceSpecTests {
    @Test func testDeclarativeThrowableStackTraceSpecsRegisterLinksAndTypes() throws {
        let (sema, interner) = try makeSema()
        let throwableFQName = ["kotlin", "Throwable"].map(interner.intern)
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))

        try assertFunction(
            named: "stackTraceToString",
            ownerFQName: throwableFQName,
            parameterTypes: [],
            returnType: sema.types.stringType,
            externalLinkName: "kk_throwable_stackTraceToString",
            receiverType: throwableType,
            sema: sema,
            interner: interner
        )
        try assertFunction(
            named: "printStackTrace",
            ownerFQName: throwableFQName,
            parameterTypes: [],
            returnType: sema.types.unitType,
            externalLinkName: "kk_throwable_printStackTrace",
            receiverType: throwableType,
            sema: sema,
            interner: interner
        )
    }

    @Test func testDeclarativeCharSpecsKeepRadixOverloadParameterMetadata() throws {
        let (sema, interner) = try makeSema()
        let digitToInt = try function(
            named: "digitToInt",
            ownerFQName: ["kotlin", "text"].map(interner.intern),
            parameterTypes: [sema.types.intType],
            receiverType: sema.types.charType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.externalLinkName(for: digitToInt) == "kk_char_digitToInt_radix")

        let signature = try #require(sema.symbols.functionSignature(for: digitToInt))
        let radixSymbol = try #require(signature.valueParameterSymbols.first)
        let radixInfo = try #require(sema.symbols.symbol(radixSymbol))
        #expect(interner.resolve(radixInfo.name) == "radix")
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
    }

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func assertFunction(
        named name: String,
        ownerFQName: [InternedString],
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws {
        let symbol = try function(
            named: name,
            ownerFQName: ownerFQName,
            parameterTypes: parameterTypes,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.externalLinkName(for: symbol) == externalLinkName)
        let signature = try #require(sema.symbols.functionSignature(for: symbol))
        #expect(signature.returnType == returnType)
    }

    private func function(
        named name: String,
        ownerFQName: [InternedString],
        parameterTypes: [TypeID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let fqName = ownerFQName + [interner.intern(name)]
        return try #require(sema.symbols.lookupAll(fqName: fqName).first {
            guard let signature = sema.symbols.functionSignature(for: $0) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        })
    }
}
#endif
