/// Synthetic UIntRange / ULongRange stub registration helpers.
///
/// Split out from `HeaderHelpers+SyntheticRangeProgressionStubs.swift`.
extension DataFlowSemaPhase {
    func registerSyntheticUIntRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("UIntRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        // KSP-1316: Keep the Companion nominal available for the bundled
        // source-backed UIntRange.Companion.EMPTY extension.
        if symbols.companionObjectSymbol(for: classSymbol) == nil {
            let companionName = interner.intern("Companion")
            let companionFQName = classFQName + [companionName]
            let companionSymbol: SymbolID
            if let imported = symbols.lookupAll(fqName: companionFQName).first {
                companionSymbol = imported
                symbols.setParentSymbol(classSymbol, for: companionSymbol)
            } else {
                companionSymbol = symbols.define(
                    kind: .object,
                    name: companionName,
                    fqName: companionFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .static]
                )
                symbols.setParentSymbol(classSymbol, for: companionSymbol)
            }
            symbols.setCompanionObjectSymbol(companionSymbol, for: classSymbol)
        }

        let rangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.uintType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.uintType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.uintType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // KSP-1523: these externalLinkNames are dead metadata for codegen — a
        // property access on a UIntRange-typed receiver is intercepted earlier,
        // in CallLowerer+LegacyMemberLikeCalls.swift, via the reliable
        // `sema.bindings.isUIntRangeExpr` marker, which already emits
        // `__kk_range_first`/`__kk_range_last` directly. Sema still needs a
        // registered property here so expressions like `r.first` type-check as
        // UInt. Keep the link names aligned to the bridge that's actually used
        // so they don't dangle on a symbol slated for removal.
        for property in [
            ("start", "__kk_range_first"),
            ("end", "__kk_range_last"),
            ("first", "__kk_range_first"),
            ("last", "__kk_range_last"),
            ("endExclusive", "__kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.uintType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.intType,
            externalLinkName: "kk_uint_range_step",
            symbols: symbols,
            interner: interner
        )

        // KSP-1523: no `contains`/`isEmpty` registration here. `isEmpty`
        // resolves via the shared `ClosedRange<T>` interface member (see
        // `closedRangeInterfaceRuntimeName` in
        // CallLowerer+MemberCallDefaultsAndResolution.swift). Confirmed by KIR
        // probe: both member names reach `__kk_range_contains`/`__kk_range_isEmpty`
        // for variable- and literal-receiver call shapes with no class-level
        // registration for either name.
        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "__kk_uint_range_iterator",
            symbols: symbols,
            interner: interner
        )
        // KSP-1523: no `reversed`/`toList`/`firstOrNull`/`lastOrNull`
        // registrations here — all four now have bundled Kotlin declarations
        // in RangeHOF.kt. Confirmed dead by marker probe (ZZZ-tagged
        // externalLinkNames, rebuilt, comprehensive real-kklib nm +
        // `--emit kir` check: zero occurrences; the Sema golden suite is
        // also unaffected by their removal). `toUIntArray`'s registration
        // was removed here too, but for a different reason: it isn't a
        // real UIntRange member in Kotlin at all — `toUIntArray()` is a
        // `Collection<UInt>` member, and UIntRange is `Iterable<UInt>` but
        // not `Collection` (confirmed via diff_kotlinc.sh: real kotlinc
        // rejects it) — so it was dropped entirely rather than migrated to
        // RangeHOF.kt.
        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "__kk_uint_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.uintType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "__kk_uint_range_drop",
            symbols: symbols,
            interner: interner
        )
        // KSP-1523: no `sorted` registration here either — same
        // bundled-overlap reasoning and marker-probe confirmation as above
        // (bundled in RangeHOF.kt). `average`'s registration was removed
        // here too, but has no bundled declaration to fall back to — real
        // kotlinc rejects `UIntRange.average()` (it exists only for
        // `Iterable<Byte/Short/Int/Long/Float/Double>`, confirmed via
        // diff_kotlinc.sh), so it was dropped entirely rather than
        // migrated.
        registerSyntheticConstructor(
            ownerSymbol: classSymbol,
            ownerType: rangeType,
            parameterTypes: [types.uintType, types.uintType],
            parameterNames: ["start", "end"],
            externalLinkName: "__kk_uint_rangeTo",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticULongRangeStub(
        rangesPackageSymbol: SymbolID,
        rangesFQName: [InternedString],
        openEndRangeSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let className = interner.intern("ULongRange")
        let classFQName = rangesFQName + [className]
        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            let created = symbols.define(
                kind: .class,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(rangesPackageSymbol, for: created)
            classSymbol = created
        }

        let rangeType = types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
        registerIterableSupertype(
            classSymbol: classSymbol,
            elementType: types.ulongType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerOpenEndRangeConformance(
            classSymbol: classSymbol,
            elementType: types.ulongType,
            openEndRangeSymbol: openEndRangeSymbol,
            symbols: symbols,
            types: types
        )
        let iteratorType = syntheticIteratorType(
            elementType: types.ulongType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        for property in [
            ("start", "__kk_range_first"),
            ("endInclusive", "__kk_range_last"),
            ("first", "__kk_range_first"),
            ("last", "__kk_range_last"),
            ("endExclusive", "__kk_range_endExclusive"),
        ] {
            registerProgressionProperty(
                named: property.0,
                ownerSymbol: classSymbol,
                propertyType: types.ulongType,
                externalLinkName: property.1,
                symbols: symbols,
                interner: interner
            )
        }
        registerProgressionProperty(
            named: "step",
            ownerSymbol: classSymbol,
            propertyType: types.intType,
            externalLinkName: "kk_ulong_range_step",
            symbols: symbols,
            interner: interner
        )

        registerProgressionMethod(
            named: "iterator",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [],
            returnType: iteratorType,
            externalLinkName: "__kk_ulong_range_iterator",
            symbols: symbols,
            interner: interner
        )
        // KSP-1524: contains/isEmpty and the aggregate/membership helpers are
        // bundled Kotlin declarations. Keep only the synthetic members that
        // have no source-backed replacement in this stub.
        registerProgressionMethod(
            named: "take",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "__kk_ulong_range_take",
            symbols: symbols,
            interner: interner
        )
        registerProgressionMethod(
            named: "drop",
            ownerSymbol: classSymbol,
            receiverType: rangeType,
            parameterTypes: [types.intType],
            returnType: syntheticListType(elementType: types.ulongType, symbols: symbols, types: types, interner: interner),
            externalLinkName: "__kk_ulong_range_drop",
            symbols: symbols,
            interner: interner
        )
    }

}

extension DataFlowSemaPhase {
    fileprivate func syntheticListType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let listSymbol = symbols.lookupByShortName(interner.intern("List")).first else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
