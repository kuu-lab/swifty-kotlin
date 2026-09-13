import RuntimeABI

/// BuilderDSL lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct BuilderDSLLookupNames {
    // Builder DSL names (STDLIB-002)
    let buildListName: InternedString
    let kkBuildListName: InternedString
    let kkBuildListWithCapacityName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        buildListName = interner.intern("buildList")
        kkBuildListName = interner.intern("__kk_build_list")
        kkBuildListWithCapacityName = interner.intern("__kk_build_list_with_capacity")
        kkMutableSetAddName = interner.intern("__kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("__kk_mutable_set_remove")
        builderDSLNames = [
            buildListName,
        ]
    }
}
