@testable import CompilerCore
import Testing

@Suite
struct ThrowableSuppressedExceptionsSyntheticTests {
    @Test
    func testThrowableSuppressedExceptionsSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0

            fun sample(e: Throwable) {
                val suppressed: List<Throwable> = e.suppressedExceptions
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let path0 = paths[0]
            let path0Diagnostics = diagnosticsForPath(path0, in: ctx)
            #expect(
                !path0Diagnostics.contains(where: { $0.severity == .error }),
                "Expected Throwable surface to resolve cleanly, got: \(path0Diagnostics)"
            )

            // === testSuppressedExceptionsRootExtensionPropertyIsRegistered ===
            do {

                let kotlinPackage = ["kotlin"].map { interner.intern($0) }
                let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

                let throwableSymbol = try #require(sema.symbols.lookup(
                    fqName: kotlinPackage + [interner.intern("Throwable")]
                ))
                let listSymbol = try #require(sema.symbols.lookup(
                    fqName: collectionsPackage + [interner.intern("List")]
                ))
                let throwableType = sema.types.make(.classType(ClassType(
                    classSymbol: throwableSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let expectedListType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(throwableType)],
                    nullability: .nonNull
                )))

                let propertySymbol = try #require(
                    sema.symbols.lookupAll(
                        fqName: kotlinPackage + [interner.intern("suppressedExceptions")]
                    ).first { symbolID in
                        sema.symbols.symbol(symbolID)?.kind == .property
                            && sema.symbols.extensionPropertyReceiverType(for: symbolID) == throwableType
                    },
                    "Expected kotlin.Throwable.suppressedExceptions root extension property"
                )
                let getterSymbol = try #require(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))

                #expect(sema.symbols.propertyType(for: propertySymbol) == expectedListType)
                #expect(sema.symbols.externalLinkName(for: propertySymbol) == "kk_throwable_suppressedExceptions")
                #expect(sema.symbols.externalLinkName(for: getterSymbol) == "kk_throwable_suppressedExceptions")
                #expect(sema.symbols.functionSignature(for: getterSymbol)?.receiverType == throwableType)
                #expect(sema.symbols.functionSignature(for: getterSymbol)?.returnType == expectedListType)
            }

            // === testSuppressedExceptionsCanBeAssignedToListOfThrowable ===
            do {

                let sampleSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("sample0"),
                    interner.intern("sample"),
                ]))

                #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
            }
        }
    }
}
