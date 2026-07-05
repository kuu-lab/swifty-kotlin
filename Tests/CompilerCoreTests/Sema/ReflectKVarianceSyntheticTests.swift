#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKVarianceSyntheticTests {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            #expect(!(ctx.diagnostics.hasError), Comment(rawValue: "Expected KVariance surface to resolve cleanly, got: \(diagnostics)"))
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKVarianceEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let enumFQName = ["kotlin", "reflect", "KVariance"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        #expect(sema.symbols.symbol(enumSymbol)?.kind == .enumClass)
        #expect(sema.symbols.symbol(enumSymbol)?.flags.contains(.synthetic) == true)

        let enumType = sema.types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))
        for entry in ["INVARIANT", "IN", "OUT"] {
            let entrySymbol = try #require(sema.symbols.lookup(fqName: enumFQName + [interner.intern(entry)]))
            #expect(sema.symbols.symbol(entrySymbol)?.kind == .field)
            #expect(sema.symbols.parentSymbol(for: entrySymbol) == enumSymbol)
            #expect(sema.symbols.propertyType(for: entrySymbol) == enumType)
        }
    }

    @Test func testKVarianceEntriesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KVariance

        fun invariantVariance(): KVariance = KVariance.INVARIANT
        fun inVariance(): KVariance = KVariance.IN
        fun outVariance(): KVariance = KVariance.OUT
        """

        _ = try makeSema(source: source)
    }
}
#endif
