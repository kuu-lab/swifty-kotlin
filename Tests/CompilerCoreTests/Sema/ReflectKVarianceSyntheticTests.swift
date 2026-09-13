#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ReflectKVarianceSyntheticTests {
    private static let fixture = SemaFixture(surface: "KVariance")

    private func sharedSema(
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared(sourceLocation: sourceLocation)
    }

    private func makeSema(
        source: String = "fun noop() {}",
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source, sourceLocation: sourceLocation)
    }

    @Test func testKVarianceEnumAndGeneratedMembersAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let enumFQName = ["kotlin", "reflect", "KVariance"].map { interner.intern($0) }
        let enumSymbol = try #require(sema.symbols.lookup(fqName: enumFQName))
        #expect(sema.symbols.symbol(enumSymbol)?.kind == .enumClass)
        #expect(sema.symbols.isSourceBackedSymbol(enumSymbol))

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

        let valuesSymbol = try #require(
            sema.symbols.lookup(fqName: enumFQName + [interner.intern("values")])
        )
        #expect(sema.symbols.symbol(valuesSymbol)?.kind == .function)
        #expect(sema.symbols.functionSignature(for: valuesSymbol)?.parameterTypes.isEmpty == true)

        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: enumSymbol))
        let companionFQName = try #require(sema.symbols.symbol(companionSymbol)?.fqName)
        let valueOfSymbol = try #require(
            sema.symbols.lookup(fqName: companionFQName + [interner.intern("valueOf")])
        )
        #expect(sema.symbols.symbol(valueOfSymbol)?.kind == .function)
        #expect(sema.symbols.functionSignature(for: valueOfSymbol)?.parameterTypes.count == 1)

        let entriesSymbol = try #require(
            sema.symbols.lookup(fqName: companionFQName + [interner.intern("entries")])
        )
        #expect(sema.symbols.symbol(entriesSymbol)?.kind == .property)
    }

    @Test func testKVarianceEntriesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KVariance

        fun invariantVariance(): KVariance = KVariance.INVARIANT
        fun inVariance(): KVariance = KVariance.IN
        fun outVariance(): KVariance = KVariance.OUT
        fun varianceEntries(): kotlin.enums.EnumEntries<KVariance> = KVariance.entries
        fun varianceValues(): Array<KVariance> = KVariance.values()
        fun varianceValueOf(): KVariance = KVariance.valueOf("IN")
        """

        _ = try makeSema(source: source)
    }
}
#endif
