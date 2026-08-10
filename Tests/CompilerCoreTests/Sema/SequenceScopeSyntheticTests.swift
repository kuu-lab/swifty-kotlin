@testable import CompilerCore
import Testing

@Suite
struct SequenceScopeSyntheticTests {

    @Test
    func testSequenceScopeSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            fun noop() {}
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testSequenceScopeSurfaceIsRegistered ===
            do {

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
    }

}
