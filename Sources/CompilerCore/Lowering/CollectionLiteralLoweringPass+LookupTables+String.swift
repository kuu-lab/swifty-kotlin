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
    let kkStringFilterName: InternedString
    let kkStringMapName: InternedString
    let kkStringCountName: InternedString
    let kkStringAnyName: InternedString
    let kkStringAllName: InternedString
    let kkStringNoneName: InternedString
    let stringProducingCallees: Set<InternedString>

    init(interner: StringInterner) {
        kkStringSplitName = interner.intern("__kk_string_split")
        kkStringAsSequenceName = interner.intern("kk_string_asSequence_flat")
        kkStringAsIterableName = interner.intern("kk_string_asIterable_flat")
        kkStringIteratorName = interner.intern("kk_string_iterator_flat")
        kkStringIteratorHasNextName = interner.intern("kk_string_iterator_hasNext")
        kkStringIteratorNextName = interner.intern("kk_string_iterator_next")
        kkStringFilterName = interner.intern("kk_string_filter")
        kkStringMapName = interner.intern("kk_string_map")
        kkStringCountName = interner.intern("kk_string_count")
        kkStringAnyName = interner.intern("kk_string_any")
        kkStringAllName = interner.intern("kk_string_all")
        kkStringNoneName = interner.intern("kk_string_none")
        stringProducingCallees = [
            interner.intern("kk_string_concat_flat"),
            interner.intern("kk_string_intern"),
            interner.intern("kk_string_lowercase"),
            interner.intern("kk_string_uppercase"),
            interner.intern("kk_string_replace_flat"),
            interner.intern("kk_string_replaceFirst_flat"),
            interner.intern("kk_string_replaceAfter_flat"),
            interner.intern("kk_string_replaceAfter_char_flat"),
            interner.intern("kk_string_replaceAfterLast_flat"),
            interner.intern("kk_string_replaceAfterLast_char_flat"),
            interner.intern("kk_string_replaceBefore_flat"),
            interner.intern("kk_string_replaceBefore_char_flat"),
            interner.intern("kk_string_replaceBeforeLast_flat"),
            interner.intern("kk_string_replaceBeforeLast_char_flat"),
            interner.intern("kk_string_substringBefore_flat"),
            interner.intern("kk_string_substringBefore_char_flat"),
            interner.intern("kk_string_substringAfter_flat"),
            interner.intern("kk_string_substringAfter_char_flat"),
            interner.intern("kk_string_substringBeforeLast_flat"),
            interner.intern("kk_string_substringBeforeLast_char_flat"),
            interner.intern("kk_string_substringAfterLast_flat"),
            interner.intern("kk_string_substringAfterLast_char_flat"),
            kkStringFilterName,
        ]
    }
}
