@testable import CompilerCore
import Testing

@Suite
struct ThrowableSuppressedExceptionsSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), "Expected Throwable surface to resolve cleanly, got: \(diagnostics)")
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test
    func testSuppressedExceptionsRootExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test
    func testSuppressedExceptionsCanBeAssignedToListOfThrowable() throws {
        let source = """
        fun sample(e: Throwable) {
            val suppressed: List<Throwable> = e.suppressedExceptions
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
    }
}
