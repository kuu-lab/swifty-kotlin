@testable import CompilerCore
import Foundation
import Testing

/// Surface coverage for STDLIB-TIME-FN-012: `DurationUnit.toTimeUnit()` and the
/// synthetic `java.util.concurrent.TimeUnit` enum it returns.
@Suite
struct TimeUnitConversionSyntheticSurfaceTests {

    @Test
    func testTimeUnitConversionSyntheticSurfaceTestsInventory() throws {
        let sources: [String] = [
            """
            package sample0
            import java.util.concurrent.TimeUnit
            import kotlin.time.DurationUnit
            import kotlin.time.toTimeUnit

            fun label(unit: DurationUnit): String = when (unit.toTimeUnit()) {
                TimeUnit.NANOSECONDS -> "ns"
                TimeUnit.MICROSECONDS -> "us"
                TimeUnit.MILLISECONDS -> "ms"
                TimeUnit.SECONDS -> "s"
                TimeUnit.MINUTES -> "min"
                TimeUnit.HOURS -> "h"
                TimeUnit.DAYS -> "d"
            }

            fun isMinutes(unit: DurationUnit): Boolean = unit.toTimeUnit() == TimeUnit.MINUTES
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx

            // === testTimeUnitEnumEntriesAreRegistered ===
            do {

                let timeUnitFQName = [
                    interner.intern("java"),
                    interner.intern("util"),
                    interner.intern("concurrent"),
                    interner.intern("TimeUnit"),
                ]
                let timeUnitSymbol = try #require(sema.symbols.lookup(fqName: timeUnitFQName))
                #expect(sema.symbols.symbol(timeUnitSymbol)?.kind == .enumClass)

                let timeUnitType = sema.types.make(.classType(ClassType(
                    classSymbol: timeUnitSymbol,
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
                    let entrySymbol = try #require(
                        sema.symbols.lookup(fqName: timeUnitFQName + [interner.intern(entry)]),
                        "TimeUnit.\(entry) must be registered"
                    )
                    #expect(sema.symbols.parentSymbol(for: entrySymbol) == timeUnitSymbol)
                    #expect(sema.symbols.propertyType(for: entrySymbol) == timeUnitType)
                }
            }

            // === testToTimeUnitExtensionFunctionIsRegistered ===
            do {

                let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("time"),
                    interner.intern("DurationUnit"),
                ]))
                let durationUnitType = sema.types.make(.classType(ClassType(
                    classSymbol: durationUnitSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let timeUnitSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("java"),
                    interner.intern("util"),
                    interner.intern("concurrent"),
                    interner.intern("TimeUnit"),
                ]))
                let timeUnitType = sema.types.make(.classType(ClassType(
                    classSymbol: timeUnitSymbol,
                    args: [],
                    nullability: .nonNull
                )))

                let toTimeUnitFQName = [
                    interner.intern("kotlin"),
                    interner.intern("time"),
                    interner.intern("toTimeUnit"),
                ]
                let functionSymbol = try #require(
                    sema.symbols.lookupAll(fqName: toTimeUnitFQName).first(where: { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.receiverType == durationUnitType
                    }),
                    "kotlin.time.toTimeUnit with a DurationUnit receiver must be registered"
                )

                let signature = try #require(sema.symbols.functionSignature(for: functionSymbol))
                #expect(signature.receiverType == durationUnitType)
                #expect(signature.returnType == timeUnitType)
                #expect(signature.parameterTypes.isEmpty)
                #expect(sema.symbols.externalLinkName(for: functionSymbol) == "kk_duration_unit_to_time_unit")
            }

            // Source compiled for testToTimeUnitResolvesInSource
            _ = diagnosticsForPath(paths[0], in: ctx)
        }
    }

}
