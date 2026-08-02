import RuntimeABI

/// String lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct StringLookupNames {
    // Set predicate HOF ABI names (STDLIB-SET-PRED)
    let kkStringSplitName: InternedString
    let kkStringAsSequenceName: InternedString
    let kkStringAsIterableName: InternedString
    let kkStringIteratorName: InternedString
    let kkStringIteratorHasNextName: InternedString
    let kkStringIteratorNextName: InternedString
    let stringProducingCallees: Set<InternedString>

    init(interner: StringInterner) {
        kkStringSplitName = interner.intern("__kk_string_split")
        kkStringAsSequenceName = interner.intern("kk_string_asSequence_flat")
        kkStringAsIterableName = interner.intern("kk_string_asIterable_flat")
        kkStringIteratorName = interner.intern("kk_string_iterator_flat")
        kkStringIteratorHasNextName = interner.intern("kk_string_iterator_hasNext")
        kkStringIteratorNextName = interner.intern("kk_string_iterator_next")
        stringProducingCallees = [
            interner.intern("kk_string_concat_flat"),
            interner.intern("kk_string_intern"),
            interner.intern("kk_string_lowercase"),
            interner.intern("kk_string_uppercase"),
            interner.intern("kk_string_replace_flat"),
            interner.intern("kk_string_replaceFirst_flat"),
        ]
    }
}
