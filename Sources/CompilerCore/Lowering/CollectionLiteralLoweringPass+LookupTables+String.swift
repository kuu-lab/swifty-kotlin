
struct StringLookupNames {
    let kkStringSplitName: InternedString
    let stringProducingCallees: Set<InternedString>

    init(interner: StringInterner) {
        kkStringSplitName = interner.intern("__kk_string_split")
        stringProducingCallees = [
            interner.intern("__kk_string_concat_flat"),
            interner.intern("__kk_string_intern"),
            interner.intern("kk_string_lowercase"),
            interner.intern("kk_string_uppercase"),
            interner.intern("kk_string_replace_flat"),
            interner.intern("kk_string_replaceFirst_flat"),
        ]
    }
}
