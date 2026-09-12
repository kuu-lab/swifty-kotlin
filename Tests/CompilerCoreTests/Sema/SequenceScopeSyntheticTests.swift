@testable import CompilerCore
import Testing

@Suite
struct SequenceScopeSyntheticTests {
    private static let fixture = SemaFixture(surface: "SequenceScope")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test func testSequenceScopeSurfaceIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let scopeSymbol = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("SequenceScope")]
        ))
        let sequenceSymbol = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("Sequence")]
        ))
        let iteratorSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterator")]
        ))
        let iterableSymbol = try #require(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("Iterable")]
        ))
        #expect(sema.symbols.symbol(scopeSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(scopeSymbol)?.flags.contains(.synthetic) == false)
        #expect(sema.symbols.isSourceBackedSymbol(scopeSymbol))

        let typeParams = sema.types.nominalTypeParameterSymbols(for: scopeSymbol)
        #expect(typeParams.count == 1)
        #expect(sema.types.nominalTypeParameterVariances(for: scopeSymbol) == [.in])

        let elementType = sema.types.make(.typeParam(TypeParamType(
            symbol: typeParams[0],
            nullability: .nonNull
        )))
        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: scopeSymbol,
            args: [.invariant(elementType)],
            nullability: .nonNull
        )))
        let yieldSymbol = try #require(sema.symbols.lookup(
            fqName: sequencePackage + [interner.intern("SequenceScope"), interner.intern("yield")]
        ))
        let yieldSignature = try #require(sema.symbols.functionSignature(for: yieldSymbol))
        #expect(yieldSignature.receiverType == receiverType)
        #expect(yieldSignature.parameterTypes == [elementType])
        #expect(yieldSignature.returnType == sema.types.unitType)
        #expect(sema.symbols.isSourceBackedSymbol(yieldSymbol))
        #expect(sema.symbols.externalLinkName(for: yieldSymbol) == nil)
        #expect(sema.symbols.symbol(yieldSymbol)?.flags.contains(.abstractType) == true)
        #expect(sema.symbols.symbol(yieldSymbol)?.flags.contains(.suspendFunction) == true)
        #expect(yieldSignature.isSuspend)

        let yieldAllSymbols = sema.symbols.lookupAll(
            fqName: sequencePackage + [interner.intern("SequenceScope"), interner.intern("yieldAll")]
        )
        #expect(yieldAllSymbols.count == 3)

        let expectedParameterTypes: Set<TypeID> = [
            sema.types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.invariant(elementType)],
                nullability: .nonNull
            ))),
        ]
        let actualParameterTypes = try Set(yieldAllSymbols.map { symbolID in
            try #require(sema.symbols.functionSignature(for: symbolID)).parameterTypes[0]
        })
        #expect(actualParameterTypes == expectedParameterTypes)
        for symbolID in yieldAllSymbols {
            let signature = try #require(sema.symbols.functionSignature(for: symbolID))
            #expect(sema.symbols.isSourceBackedSymbol(symbolID))
            #expect(sema.symbols.externalLinkName(for: symbolID) == nil)
            #expect(sema.symbols.symbol(symbolID)?.flags.contains(.suspendFunction) == true)
            #expect(signature.isSuspend)
        }
    }
}
