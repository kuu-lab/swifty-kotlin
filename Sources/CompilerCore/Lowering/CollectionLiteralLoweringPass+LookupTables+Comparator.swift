import RuntimeABI

/// Comparator lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct ComparatorLookupNames {
    // Comparator ABI names (STDLIB-175, STDLIB-177, STDLIB-613)
    let kkComparatorFromMultiSelectorsName: InternedString
    let kkComparatorFromMultiSelectors3Name: InternedString
    let kkComparatorFromMultiSelectorsVarargName: InternedString
    let kkComparatorFromMultiSelectorsTrampolineName: InternedString
    let kkComparatorNullsFirstName: InternedString
    let kkComparatorNullsLastName: InternedString
    let kkComparatorNullsFirstTrampolineName: InternedString
    let kkComparatorNullsLastTrampolineName: InternedString
    let kkComparatorNullsFirstComparableName: InternedString
    let kkComparatorNullsFirstComparableTrampolineName: InternedString
    let kkComparatorNullsLastNaturalName: InternedString
    let kkComparatorNullsLastNaturalTrampolineName: InternedString

    init(interner: StringInterner) {
        kkComparatorFromMultiSelectorsName = interner.intern("kk_comparator_from_multi_selectors")
        kkComparatorFromMultiSelectors3Name = interner.intern("kk_comparator_from_multi_selectors3")
        kkComparatorFromMultiSelectorsVarargName = interner.intern("kk_comparator_from_multi_selectors_vararg")
        kkComparatorFromMultiSelectorsTrampolineName = interner.intern("kk_comparator_from_multi_selectors_trampoline")
        kkComparatorNullsFirstName = interner.intern("kk_comparator_nulls_first")
        kkComparatorNullsLastName = interner.intern("kk_comparator_nulls_last")
        kkComparatorNullsFirstTrampolineName = interner.intern("kk_comparator_nulls_first_trampoline")
        kkComparatorNullsLastTrampolineName = interner.intern("kk_comparator_nulls_last_trampoline")
        kkComparatorNullsFirstComparableName = interner.intern("kk_comparator_nulls_first_comparable")
        kkComparatorNullsFirstComparableTrampolineName = interner.intern("kk_comparator_nulls_first_comparable_trampoline")
        kkComparatorNullsLastNaturalName = interner.intern("kk_comparator_nulls_last_natural")
        kkComparatorNullsLastNaturalTrampolineName = interner.intern("kk_comparator_nulls_last_natural_trampoline")
    }
}
