@testable import CompilerCore
import Testing

@Suite
struct ThrowablePrintStackTraceSyntheticTests {
    private static let fixture = SemaFixture(surface: "Throwable")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test
    func testPrintStackTraceMemberFunctionIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let kotlinPackage = ["kotlin"].map { interner.intern($0) }
        let throwableSymbol = try #require(sema.symbols.lookup(
            fqName: kotlinPackage + [interner.intern("Throwable")]
        ))
        let throwableType = sema.types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))

        let printStackTraceSymbol = try #require(
            sema.symbols.lookupAll(
                fqName: kotlinPackage + [interner.intern("printStackTrace")]
            ).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .function
                    && sema.symbols.functionSignature(for: symbolID)?.receiverType == throwableType
            },
            "Expected kotlin.Throwable.printStackTrace extension function"
        )
        let signature = try #require(sema.symbols.functionSignature(for: printStackTraceSymbol))

        let symbol = try #require(sema.symbols.symbol(printStackTraceSymbol))
        #expect(!symbol.flags.contains(.synthetic))
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
