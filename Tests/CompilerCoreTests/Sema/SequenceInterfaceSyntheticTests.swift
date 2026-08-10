@testable import CompilerCore
import Testing

@Suite
struct SequenceInterfaceSyntheticTests {

    @Test
    func testSequenceInterfaceSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.collections.Iterator
            import kotlin.sequences.Sequence

            fun <T> iteratorOf(values: Sequence<T>): Iterator<T> =
                values.iterator()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testSequenceInterfaceSurfaceIsRegistered ===
            do {

                let sequencePackage = ["kotlin", "sequences"].map { interner.intern($0) }
                let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

                let sequenceSymbol = try #require(sema.symbols.lookup(
                    fqName: sequencePackage + [interner.intern("Sequence")]
                ))
                let iteratorSymbol = try #require(sema.symbols.lookup(
                    fqName: collectionsPackage + [interner.intern("Iterator")]
                ))
                let sequenceInfo = try #require(sema.symbols.symbol(sequenceSymbol))
                #expect(sequenceInfo.kind == .interface)
                #expect(!sequenceInfo.flags.contains(.synthetic))

                let typeParams = sema.types.nominalTypeParameterSymbols(for: sequenceSymbol)
                #expect(typeParams.count == 1)
                #expect(sema.types.nominalTypeParameterVariances(for: sequenceSymbol) == [.out])

                let elementType = sema.types.make(.typeParam(TypeParamType(
                    symbol: typeParams[0],
                    nullability: .nonNull
                )))
                let receiverType = sema.types.make(.classType(ClassType(
                    classSymbol: sequenceSymbol,
                    args: [.out(elementType)],
                    nullability: .nonNull
                )))
                let iteratorType = sema.types.make(.classType(ClassType(
                    classSymbol: iteratorSymbol,
                    args: [.out(elementType)],
                    nullability: .nonNull
                )))

                let iteratorMember = try #require(sema.symbols.lookup(
                    fqName: sequencePackage + [interner.intern("Sequence"), interner.intern("iterator")]
                ))
                #expect(sema.symbols.symbol(iteratorMember)?.flags.contains(.operatorFunction) == true)
                let signature = try #require(sema.symbols.functionSignature(for: iteratorMember))
                let signatureReceiver = try #require(signature.receiverType)
                #expect(sema.types.isSubtype(signatureReceiver, receiverType) && sema.types.isSubtype(receiverType, signatureReceiver))
                #expect(signature.parameterTypes == [])
                #expect(sema.types.isSubtype(signature.returnType, iteratorType) && sema.types.isSubtype(iteratorType, signature.returnType))
                #expect(signature.typeParameterSymbols == typeParams)
                #expect(signature.classTypeParameterCount == 1)
            }

            // === testSequenceIteratorResolvesInSource ===
            do {
                let path0 = paths[0]
                let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
                #expect(!path0Diagnostics.contains(where: { $0.severity == .error }), "Expected testSequenceIteratorResolvesInSource to resolve cleanly, got: \(path0Diagnostics)")
            }
        }
    }

}
