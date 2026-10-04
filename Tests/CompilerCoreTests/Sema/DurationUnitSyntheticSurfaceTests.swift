#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DurationUnitSyntheticSurfaceTests {
    private static let fixture = SemaFixture(surface: "DurationUnit", diagnostics: .noDiagnostics)

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

    @Test func testDurationUnitEnumEntriesAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("DurationUnit"),
        ]))
        #expect(sema.symbols.symbol(durationUnitSymbol)?.kind == .enumClass)

        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let entries = [
            "NANOSECONDS",
            "MICROSECONDS",
            "MILLISECONDS",
            "SECONDS",
            "MINUTES",
            "HOURS",
            "DAYS",
        ]
        for entry in entries {
            let entrySymbol = try #require(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("time"),
                interner.intern("DurationUnit"),
                interner.intern(entry),
            ]), "DurationUnit.\(entry) must be registered")
            #expect(sema.symbols.parentSymbol(for: entrySymbol) == durationUnitSymbol)
            #expect(sema.symbols.propertyType(for: entrySymbol) == durationUnitType)
        }
    }

    @Test func testDurationUnitEntriesResolveInSource() throws {
        let source = """
        import kotlin.time.DurationUnit

        fun secondsUnit(): DurationUnit = DurationUnit.SECONDS

        fun unitIndex(unit: DurationUnit): Int = when (unit) {
            DurationUnit.NANOSECONDS -> 0
            DurationUnit.MICROSECONDS -> 1
            DurationUnit.MILLISECONDS -> 2
            DurationUnit.SECONDS -> 3
            DurationUnit.MINUTES -> 4
            DurationUnit.HOURS -> 5
            DurationUnit.DAYS -> 6
        }
        """

        _ = try makeSema(source: source)
    }
}
#endif
