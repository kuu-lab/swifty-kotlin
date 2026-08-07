@testable import CompilerCore
import Testing

@Suite
struct ThrowablePrintStackTraceSyntheticTests {
    @Test
    func testThrowablePrintStackTraceSyntheticTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0

            fun sample(e: Throwable) {
                val result: Unit = e.printStackTrace()
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

            // === testPrintStackTraceMemberFunctionIsRegistered ===
            do {

                let kotlinPackage = ["kotlin"].map { interner.intern($0) }
                let throwableSymbol = try #require(sema.symbols.lookup(
                    fqName: kotlinPackage + [interner.intern("Throwable")]
                ))
                let throwableType = sema.types.make(.classType(ClassType(
                    classSymbol: throwableSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let printStackTraceSymbol = try #require(sema.symbols.lookup(
                    fqName: kotlinPackage + [interner.intern("Throwable"), interner.intern("printStackTrace")]
                ))
                let signature = try #require(sema.symbols.functionSignature(for: printStackTraceSymbol))

                #expect(sema.symbols.externalLinkName(for: printStackTraceSymbol) == "kk_throwable_printStackTrace")
                #expect(signature.receiverType == throwableType)
                #expect(signature.parameterTypes == [])
                #expect(signature.returnType == sema.types.unitType)
            }

            // === testPrintStackTraceResolvesAsUnitReturningMemberCall ===
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
