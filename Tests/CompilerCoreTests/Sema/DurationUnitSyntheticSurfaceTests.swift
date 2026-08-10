#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct DurationUnitSyntheticSurfaceTests {

    @Test
    func testDurationUnitSyntheticSurfaceTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
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
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testDurationUnitEnumEntriesAreRegistered ===
            do {

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

            // Source compiled for testDurationUnitEntriesResolveInSource
            _ = diagnosticsForPath(paths[0], in: ctx)
        }
    }

}
#endif
