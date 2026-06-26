@testable import CompilerCore
import Foundation
import XCTest

/// Surface coverage for STDLIB-TIME-FN-012: `DurationUnit.toTimeUnit()` and the
/// synthetic `java.util.concurrent.TimeUnit` enum it returns.
final class TimeUnitConversionSyntheticSurfaceTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertTrue(
                ctx.diagnostics.diagnostics.isEmpty,
                "Expected TimeUnit surface source to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testTimeUnitEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let timeUnitFQName = [
            interner.intern("java"),
            interner.intern("util"),
            interner.intern("concurrent"),
            interner.intern("TimeUnit"),
        ]
        let timeUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: timeUnitFQName))
        XCTAssertEqual(sema.symbols.symbol(timeUnitSymbol)?.kind, .enumClass)

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
            let entrySymbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: timeUnitFQName + [interner.intern(entry)]),
                "TimeUnit.\(entry) must be registered"
            )
            XCTAssertEqual(sema.symbols.parentSymbol(for: entrySymbol), timeUnitSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: entrySymbol), timeUnitType)
        }
    }

    func testToTimeUnitExtensionFunctionIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let durationUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("time"),
            interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let timeUnitSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [
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
        let functionSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: toTimeUnitFQName).first(where: { symbolID in
                guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == durationUnitType
            }),
            "kotlin.time.toTimeUnit with a DurationUnit receiver must be registered"
        )

        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: functionSymbol))
        XCTAssertEqual(signature.receiverType, durationUnitType)
        XCTAssertEqual(signature.returnType, timeUnitType)
        XCTAssertTrue(signature.parameterTypes.isEmpty)
        XCTAssertEqual(sema.symbols.externalLinkName(for: functionSymbol), "kk_duration_unit_to_time_unit")
    }

    func testToTimeUnitResolvesInSource() throws {
        let source = """
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
        """

        _ = try makeSema(source: source)
    }
}
