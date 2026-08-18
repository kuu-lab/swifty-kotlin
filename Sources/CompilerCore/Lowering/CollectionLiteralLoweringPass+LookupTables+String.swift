import RuntimeABI

/// String lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct StringLookupNames {
    // Set predicate HOF ABI names (STDLIB-SET-PRED)
    let kkStringSplitName: InternedString
    let stringProducingCallees: Set<InternedString>

    init(interner: StringInterner) {
        kkStringSplitName = interner.intern("__kk_string_split")
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
