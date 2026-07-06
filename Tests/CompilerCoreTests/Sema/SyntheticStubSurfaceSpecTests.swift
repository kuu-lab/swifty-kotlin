#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SyntheticStubSurfaceSpecTests {
    @Test func testDeclarativeThrowableMemberSpecsRegisterLinksAndTypes() throws {
        let (sema, interner) = try makeSema()
        let throwableFQName = ["kotlin", "Throwable"].map(interner.intern)
        let throwableSymbol = try #require(sema.symbols.lookup(fqName: throwableFQName))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableThrowableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nullable
        )))

        let message = try property(named: "message", ownerFQName: throwableFQName, sema: sema, interner: interner)
        #expect(sema.symbols.externalLinkName(for: message) == "kk_throwable_message")
        #expect(sema.symbols.propertyType(for: message) == sema.types.makeNullable(sema.types.stringType))

        let cause = try property(named: "cause", ownerFQName: throwableFQName, sema: sema, interner: interner)
        #expect(sema.symbols.externalLinkName(for: cause) == "kk_throwable_cause")
        #expect(sema.symbols.propertyType(for: cause) == nullableThrowableType)

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
        try assertFunction(
            named: "initCause",
            ownerFQName: throwableFQName,
            parameterTypes: [nullableThrowableType],
            returnType: throwableType,
            externalLinkName: "kk_throwable_initCause",
            receiverType: throwableType,
            sema: sema,
            interner: interner
        )
        try assertFunction(
            named: "addSuppressed",
            ownerFQName: throwableFQName,
            parameterTypes: [throwableType],
            returnType: sema.types.unitType,
            externalLinkName: "kk_throwable_addSuppressed",
            receiverType: throwableType,
            sema: sema,
            interner: interner
        )

        let getSuppressed = try function(
            named: "getSuppressed",
            ownerFQName: throwableFQName,
            parameterTypes: [],
            receiverType: throwableType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.externalLinkName(for: getSuppressed) == "kk_throwable_getSuppressed")
        let signature = try #require(sema.symbols.functionSignature(for: getSuppressed))
        guard case let .classType(arrayType) = sema.types.kind(of: signature.returnType) else {
            Issue.record("Expected getSuppressed() to return Array<Throwable>")
            return
        }
        let arraySymbol = try #require(sema.symbols.symbol(arrayType.classSymbol))
        #expect(interner.resolve(arraySymbol.name) == "Array")
        #expect(arrayType.args == [.invariant(throwableType)])
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

    private func property(
        named name: String,
        ownerFQName: [InternedString],
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        let fqName = ownerFQName + [interner.intern(name)]
        return try #require(sema.symbols.lookupAll(fqName: fqName).first {
            sema.symbols.symbol($0)?.kind == .property
        })
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
