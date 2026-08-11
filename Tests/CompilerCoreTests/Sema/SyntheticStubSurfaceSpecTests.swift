#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SyntheticStubSurfaceSpecTests {
    // KSP-662: digitToInt(radix) moved to bundled Kotlin, so use the remaining
    // one-argument declarative Char spec compareTo(other) to verify parameter metadata.
    @Test func testDeclarativeCharSpecsKeepOverloadParameterMetadata() throws {
        let (sema, interner) = try makeSema()
        let compareTo = try function(
            named: "compareTo",
            ownerFQName: ["kotlin", "text"].map(interner.intern),
            parameterTypes: [sema.types.charType],
            receiverType: sema.types.charType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.externalLinkName(for: compareTo) == "kk_char_compareTo")

        let signature = try #require(sema.symbols.functionSignature(for: compareTo))
        let otherSymbol = try #require(signature.valueParameterSymbols.first)
        let otherInfo = try #require(sema.symbols.symbol(otherSymbol))
        #expect(interner.resolve(otherInfo.name) == "other")
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
