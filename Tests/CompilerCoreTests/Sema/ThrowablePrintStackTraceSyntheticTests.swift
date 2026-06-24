@testable import CompilerCore
import Testing

@Suite
struct ThrowablePrintStackTraceSyntheticTests {
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
    func testPrintStackTraceMemberFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()
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

    @Test
    func testPrintStackTraceResolvesAsUnitReturningMemberCall() throws {
        let source = """
        fun sample(e: Throwable) {
            val result: Unit = e.printStackTrace()
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let sampleSymbol = try #require(sema.symbols.lookup(
            fqName: [interner.intern("sample")]
        ))

        #expect(sema.symbols.functionSignature(for: sampleSymbol) != nil)
    }
}
