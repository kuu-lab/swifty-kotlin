@testable import CompilerCore
import Testing

@Suite
struct SequenceScopeSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!ctx.diagnostics.hasError, "Expected SequenceScope surface to resolve cleanly, got: \(diagnostics)")
            result = try (ctx.sema!, ctx.interner)
        }
        return try #require(result)
    }

    @Test func testSequenceScopeSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
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
        #expect(sema.symbols.symbol(scopeSymbol)?.flags.contains(.synthetic) == true)

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

        let yieldAllSymbols = sema.symbols.lookupAll(
            fqName: sequencePackage + [interner.intern("SequenceScope"), interner.intern("yieldAll")]
        )
        #expect(yieldAllSymbols.count == 3)

        let expectedParameterTypes: Set<TypeID> = [
            sema.types.make(.classType(ClassType(
                classSymbol: iteratorSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: iterableSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
            sema.types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            ))),
        ]
        let actualParameterTypes = try Set(yieldAllSymbols.map { symbolID in
            try #require(sema.symbols.functionSignature(for: symbolID)).parameterTypes[0]
        })
        #expect(actualParameterTypes == expectedParameterTypes)
    }
}
