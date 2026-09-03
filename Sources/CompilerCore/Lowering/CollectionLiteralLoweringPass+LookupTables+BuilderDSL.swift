import RuntimeABI

/// BuilderDSL lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct BuilderDSLLookupNames {
    // Builder DSL names (STDLIB-002)
    let buildListName: InternedString
    let buildSetName: InternedString
    let buildMapName: InternedString
    let kkBuildListName: InternedString
    let kkBuildListWithCapacityName: InternedString
    let kkBuildSetName: InternedString
    let kkBuildSetWithCapacityName: InternedString
    let kkBuildMapName: InternedString
    let kkBuildMapWithCapacityName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        buildListName = interner.intern("buildList")
        buildSetName = interner.intern("buildSet")
        buildMapName = interner.intern("buildMap")
        kkBuildListName = interner.intern("__kk_build_list")
        kkBuildListWithCapacityName = interner.intern("__kk_build_list_with_capacity")
        kkBuildSetName = interner.intern("__kk_build_set")
        kkBuildSetWithCapacityName = interner.intern("__kk_build_set_with_capacity")
        kkBuildMapName = interner.intern("__kk_build_map")
        kkBuildMapWithCapacityName = interner.intern("__kk_build_map_with_capacity")
        kkMutableSetAddName = interner.intern("__kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("__kk_mutable_set_remove")
        builderDSLNames = [
            buildListName,
            buildSetName,
            buildMapName,
        ]
    }
}
