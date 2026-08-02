import RuntimeABI

/// Set lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct SetLookupNames {
    let setOfName: InternedString
    let setOfNotNullName: InternedString
    let mutableSetOfName: InternedString
    let linkedSetOfName: InternedString
    let hashSetOfName: InternedString
    let emptySetName: InternedString
    let hashSetName: InternedString
    let linkedHashSetName: InternedString
    let kkEmptySetName: InternedString
    let kkSetOfName: InternedString
    let kkSetOfNotNullName: InternedString
    let kkSetSizeName: InternedString
    let kkSetContainsName: InternedString
    let kkSetContainsAllName: InternedString
    let kkSetIsEmptyName: InternedString
    let kkSetToStringName: InternedString
    let kkIterableToMutableSetName: InternedString
    // Set higher-order function ABI names (STDLIB-268)
    let kkSetToListName: InternedString
    let kkSetSortedName: InternedString
    let setFactoryNames: Set<InternedString>
    let mutableSetConstructorNames: Set<InternedString>

    init(interner: StringInterner) {
        setOfName = interner.intern("setOf")
        setOfNotNullName = interner.intern("setOfNotNull")
        mutableSetOfName = interner.intern("mutableSetOf")
        linkedSetOfName = interner.intern("linkedSetOf")
        hashSetOfName = interner.intern("hashSetOf")
        emptySetName = interner.intern("emptySet")
        hashSetName = interner.intern("HashSet")
        linkedHashSetName = interner.intern("LinkedHashSet")
        kkEmptySetName = interner.intern("__kk_emptySet")
        kkSetOfName = interner.intern("__kk_set_of")
        kkSetOfNotNullName = interner.intern("kk_set_of_not_null")
        kkSetSizeName = interner.intern("kk_set_size")
        kkSetContainsName = interner.intern("kk_set_contains")
        kkSetContainsAllName = interner.intern("kk_set_containsAll")
        kkSetIsEmptyName = interner.intern("kk_set_is_empty")
        kkSetToStringName = interner.intern("kk_set_to_string")
        kkIterableToMutableSetName = interner.intern("kk_iterable_toMutableSet")
        kkSetToListName = interner.intern("kk_set_toList")
        kkSetSortedName = interner.intern("kk_set_sorted")
        setFactoryNames = [setOfName, setOfNotNullName, mutableSetOfName, hashSetOfName, linkedSetOfName, emptySetName]
        mutableSetConstructorNames = [hashSetName, linkedHashSetName]
    }
}
