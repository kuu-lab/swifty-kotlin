#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DurationUnitSyntheticSurfaceTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected DurationUnit surface source to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testDurationUnitEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
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
