@testable import CompilerCore
import Foundation
import XCTest

final class DurationUnitSyntheticSurfaceTests: XCTestCase {
    func testDurationUnitEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("DurationUnit"),
        ]))
        XCTAssertEqual(sema.symbols.symbol(durationUnitSymbol)?.kind, .enumClass)

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
            let entrySymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("time"),
                interner.intern("DurationUnit"),
                interner.intern(entry),
            ]), "DurationUnit.\(entry) must be registered")
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), durationUnitSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), durationUnitType)
        }
    }

    func testDurationUnitEntriesResolveInSource() throws {
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
