#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - STDLIB-COMP-001: kotlin.comparisons API Surface Inventory
//
// This file fixes the canonical API list for kotlin.comparisons and kotlin.Comparator
// and verifies that every symbol is (or is not) registered after sema.
//
// Coverage:
//   • Comparator<T> interface: compare, thenBy, thenByDescending, thenComparator,
//     thenDescending, reversed
//   • Factory top-levels: compareBy (single-selector & vararg), compareByDescending,
//     naturalOrder, reverseOrder, nullsFirst, nullsLast
//   • Comparison top-levels: compareValues, compareValuesBy (selector / vararg / comparator)
//   • minOf / maxOf with Comparator overloads (kotlin.comparisons package)
//   • coerceIn range overloads (kotlin.ranges — inventory-level cross-check only)
//
// Scope: sema / symbol-table level only.
//   Runtime correctness is in RuntimeComparatorTests (COMP-003 / #1202).
//   Overload resolution is in ComparatorOverloadResolutionTests (COMP-002 / #1257).
//
// Gap convention:
//   APIs not yet registered by the sema layer are marked with `_Gap` suffix and
//   assert the *current absence* with a short follow-up note. Flip `XCTAssertNil` /
//   `#expect(links.isEmpty)` to the positive assertion once implemented.

@Suite
struct ComparisonsAPISurfaceInventoryTests {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    // MARK: - Lookup helpers

    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    private func symbolExists(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookup(fqName: interned) != nil
    }

    private func hasSourceBackedFunction(
        fqPath: [String],
        parameterCount: Int? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: interned).contains { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil else {
                return false
            }
            guard let parameterCount else {
                return true
            }
            return sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == parameterCount
        }
    }

    private func hasSourceBackedVarargFunction(
        fqPath: [String],
        parameterCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let interned = fqPath.map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: interned).contains { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  signature.parameterTypes.count == parameterCount
            else {
                return false
            }
            return signature.valueParameterIsVararg.last == true
        }
    }

    private func hasComparatorReceiver(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName.map { interner.resolve($0) } == ["kotlin", "Comparator"]
    }

    private func hasSourceBackedComparatorExtension(
        _ name: String,
        parameterCount: Int? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let interned = ["kotlin", "comparisons", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: interned).contains { symbolID in
            guard sema.symbols.externalLinkName(for: symbolID) == nil,
                  let signature = sema.symbols.functionSignature(for: symbolID),
                  let receiver = signature.receiverType,
                  hasComparatorReceiver(receiver, sema: sema, interner: interner)
            else {
                return false
            }
            guard let parameterCount else {
                return true
            }
            return signature.parameterTypes.count == parameterCount
        }
    }

    // MARK: - 1. kotlin.Comparator interface

    @Test func testComparatorInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(symbolExists(fqPath: ["kotlin", "Comparator"], sema: sema, interner: interner), "kotlin.Comparator interface must be registered in symbol table")
    }

    @Test func testComparatorCompareMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(symbolExists(fqPath: ["kotlin", "Comparator", "compare"], sema: sema, interner: interner), "kotlin.Comparator.compare must be registered")
    }

    // MARK: - 2. Comparator member: thenBy

    @Test func testComparatorThenByIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedComparatorExtension(
            "thenBy",
            sema: sema,
            interner: interner
        ), "Comparator.thenBy must be registered from bundled stdlib source")
    }

    // MARK: - 3. Comparator member: thenByDescending

    @Test func testComparatorThenByDescendingIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedComparatorExtension(
            "thenByDescending",
            sema: sema,
            interner: interner
        ), "Comparator.thenByDescending must be registered from bundled stdlib source")
    }

    // MARK: - 4. Comparator member: thenComparator

    @Test func testComparatorThenComparatorIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedComparatorExtension(
            "thenComparator",
            sema: sema,
            interner: interner
        ), "Comparator.thenComparator must be source-backed")
    }

    // MARK: - 5. Comparator member: thenDescending

    @Test func testComparatorThenDescendingIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedComparatorExtension(
            "thenDescending",
            sema: sema,
            interner: interner
        ), "Comparator.thenDescending must be source-backed")
    }

    // MARK: - 6. Comparator member: reversed

    @Test func testComparatorReversedIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedComparatorExtension(
            "reversed",
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "Comparator.reversed must be source-backed")
    }

    // MARK: - 7. Top-level: nullsFirst

    @Test func testNullsFirstIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "nullsFirst"],
            parameterCount: 1,
            sema: sema,
            interner: interner
        ), "nullsFirst(comparator) must be source-backed")
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "nullsFirst"],
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "nullsFirst<T : Comparable<T>>() must be source-backed")
        #expect(hasSourceBackedComparatorExtension(
            "nullsFirst",
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "Comparator<T>.nullsFirst() must be source-backed")
        #expect(!symbolExists(
            fqPath: ["kotlin", "Comparator", "nullsFirst"],
            sema: sema,
            interner: interner
        ), "nullsFirst must no longer be a synthetic Comparator member")
    }

    // MARK: - 8. Top-level: nullsLast

    @Test func testNullsLastIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "nullsLast"],
            parameterCount: 1,
            sema: sema,
            interner: interner
        ), "nullsLast(comparator) must be source-backed")
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "nullsLast"],
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "nullsLast<T : Comparable<T>>() must be source-backed")
        #expect(hasSourceBackedComparatorExtension(
            "nullsLast",
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "Comparator<T>.nullsLast() must be source-backed")
        #expect(!symbolExists(
            fqPath: ["kotlin", "Comparator", "nullsLast"],
            sema: sema,
            interner: interner
        ), "nullsLast must no longer be a synthetic Comparator member")
    }

    // MARK: - 9. Factory: compareBy (single-selector)

    @Test func testCompareByTopLevelIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            parameterCount: 1,
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.compareBy (single-selector) must be registered from bundled stdlib source")
    }

    // MARK: - 10. Factory: compareBy primitive variant removed

    @Test func testCompareByPrimitiveVariantIsNotRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(!symbolExists(
            fqPath: ["kotlin", "comparisons", "compareByPrimitive"],
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.compareByPrimitive should not be registered after KSP-309 source migration")
    }

    // MARK: - 11. Factory: compareByDescending (single-selector)

    @Test func testCompareByDescendingTopLevelIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareByDescending"],
            parameterCount: 1,
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.compareByDescending must be registered from bundled stdlib source")
    }

    // MARK: - 12. Factory: compareBy with multiple selectors (vararg)

    @Test func testCompareByVarargSelectorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedVarargFunction(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            parameterCount: 1,
            sema: sema,
            interner: interner
        ), "compareBy(vararg selectors) must be source-backed")
    }

    // MARK: - 13. Factory: compareBy with comparator + selector

    @Test func testCompareByComparatorSelectorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareBy"],
            parameterCount: 2,
            sema: sema,
            interner: interner
        ), "compareBy(comparator, selector) must be source-backed")
    }

    // MARK: - 14. Factory: naturalOrder

    @Test func testNaturalOrderIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "naturalOrder"],
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.naturalOrder must be registered from bundled stdlib source")
    }

    // MARK: - 15. Factory: reverseOrder

    @Test func testReverseOrderIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "reverseOrder"],
            parameterCount: 0,
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.reverseOrder must be registered from bundled stdlib source")
    }

    // MARK: - 16. compareValues (2 nullable args -> Int)

    @Test func testCompareValuesIsRegisteredFromBundledStdlib() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareValues"],
            parameterCount: 2,
            sema: sema,
            interner: interner
        ), "kotlin.comparisons.compareValues must be source-backed")
    }

    // MARK: - 17. compareValuesBy (single selector)

    @Test func testCompareValuesBySingleSelectorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            parameterCount: 3,
            sema: sema,
            interner: interner
        ), "compareValuesBy(a, b, selector) must be source-backed")
    }

    // MARK: - 18. compareValuesBy (vararg selectors)

    @Test func testCompareValuesByVarargIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedVarargFunction(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            parameterCount: 3,
            sema: sema,
            interner: interner
        ), "compareValuesBy(a, b, vararg selectors) must be source-backed")
    }

    // MARK: - 19. compareValuesBy (comparator + selector)

    @Test func testCompareValuesByComparatorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasSourceBackedFunction(
            fqPath: ["kotlin", "comparisons", "compareValuesBy"],
            parameterCount: 4,
            sema: sema,
            interner: interner
        ), "compareValuesBy(a, b, comparator, selector) must be source-backed")
    }

    // MARK: - 20. minOf / maxOf with Comparator (2-arg comparator overload)

    /// True when a 3-parameter overload exists whose last parameter is `kotlin.Comparator`
    /// (excludes primitive-only 3-arg overloads such as `minOf(a, b, c)`).
    private func hasThreeParamComparatorOverload(
        comparisonsName: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let fq = ["kotlin", "comparisons", comparisonsName].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let comparatorFQName = ["kotlin", "Comparator"].map { interner.intern($0) }
        guard let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) else {
            return false
        }
        return syms.contains { sym in
            guard let sig = sema.symbols.functionSignature(for: sym),
                  sig.parameterTypes.count == 3,
                  let lastParamType = sig.parameterTypes.last
            else { return false }
            if case let .classType(ct) = sema.types.kind(of: lastParamType) {
                return ct.classSymbol == comparatorSymbol
            }
            return false
        }
    }

    @Test func testMaxOfWithComparatorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasThreeParamComparatorOverload(comparisonsName: "maxOf", sema: sema, interner: interner), "kotlin.comparisons.maxOf must have a 3-param (a, b, Comparator<T>) overload")
    }

    @Test func testMinOfWithComparatorOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        #expect(hasThreeParamComparatorOverload(comparisonsName: "minOf", sema: sema, interner: interner), "kotlin.comparisons.minOf must have a 3-param (a, b, Comparator<T>) overload")
    }

    // MARK: - 21. coerceIn range overloads (kotlin.ranges cross-inventory)

    @Test func testCoerceInIntOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        #expect(links.contains("kk_int_coerceIn"), "kotlin.ranges.coerceIn (Int) must link to kk_int_coerceIn; found: \(links)")
    }

    @Test func testCoerceInLongOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        #expect(links.contains("kk_long_coerceIn"), "kotlin.ranges.coerceIn (Long) must link to kk_long_coerceIn; found: \(links)")
    }

    @Test func testCoerceInDoubleOverloadIsRegistered() throws {
        // MIGRATION-RANGE-003: Double.coerceIn(min,max) migrated to bundled Kotlin source
        // (RangeCoercion.kt). The synthetic stub with kk_double_coerceIn no longer exists;
        // verify no stale stub was left behind.
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        #expect(!links.contains("kk_double_coerceIn"), "Double.coerceIn(min,max) should not have a synthetic stub; migrated to Kotlin source")
    }

    @Test func testCoerceInFloatOverloadIsRegistered() throws {
        // MIGRATION-RANGE-003: Float.coerceIn(min,max) migrated to bundled Kotlin source
        // (RangeCoercion.kt). The synthetic stub with kk_float_coerceIn no longer exists;
        // verify no stale stub was left behind.
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "ranges", "coerceIn"],
            sema: sema,
            interner: interner
        )
        #expect(!links.contains("kk_float_coerceIn"), "Float.coerceIn(min,max) should not have a synthetic stub; migrated to Kotlin source")
    }

    // MARK: - 22. Mandatory API completeness assertion

    @Test func testAllMandatoryComparatorAPISymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let sourceBackedComparatorMembers = [
            "thenBy",
            "thenByDescending",
            "thenComparator",
            "thenDescending",
            "reversed",
            "nullsFirst",
            "nullsLast",
        ]
        for name in sourceBackedComparatorMembers {
            #expect(
                hasSourceBackedComparatorExtension(name, sema: sema, interner: interner),
                "Missing source-backed comparator extension: kotlin.comparisons.\(name)"
            )
        }

        let sourceBackedFactories: [[String]] = [
            ["kotlin", "comparisons", "compareBy"],
            ["kotlin", "comparisons", "compareByDescending"],
            ["kotlin", "comparisons", "naturalOrder"],
            ["kotlin", "comparisons", "reverseOrder"],
            ["kotlin", "comparisons", "nullsFirst"],
            ["kotlin", "comparisons", "nullsLast"],
            ["kotlin", "comparisons", "compareValues"],
            ["kotlin", "comparisons", "compareValuesBy"],
        ]
        for path in sourceBackedFactories {
            #expect(hasSourceBackedFunction(fqPath: path, sema: sema, interner: interner), "Missing source-backed factory: \(path.joined(separator: "."))")
        }

        // KSP-461: the whole kotlin.comparisons surface is source-backed; no
        // comparator symbol may keep a kk_* runtime link.
        for path in sourceBackedFactories {
            let links = allExternalLinks(fqPath: path, sema: sema, interner: interner)
            #expect(links.isEmpty, "\(path.joined(separator: ".")) must not keep runtime links; found: \(links)")
        }
    }
}
#endif
