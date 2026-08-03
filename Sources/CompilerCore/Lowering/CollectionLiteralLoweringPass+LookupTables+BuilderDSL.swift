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
    let kkBuildMapName: InternedString
    // Builder member function names (STDLIB-002)
    let addAllName: InternedString
    let putName: InternedString
    let kkBuilderListAddName: InternedString
    let kkBuilderListAddAllName: InternedString
    let kkBuilderSetAddName: InternedString
    let kkBuilderSetAddAllName: InternedString
    let kkBuilderMapPutName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        buildListName = interner.intern("buildList")
        buildSetName = interner.intern("buildSet")
        buildMapName = interner.intern("buildMap")
        kkBuildListName = interner.intern("kk_build_list")
        kkBuildListWithCapacityName = interner.intern("kk_build_list_with_capacity")
        kkBuildSetName = interner.intern("kk_build_set")
        kkBuildMapName = interner.intern("kk_build_map")
        addAllName = interner.intern("addAll")
        putName = interner.intern("put")
        kkBuilderListAddName = interner.intern("kk_builder_list_add")
        kkBuilderListAddAllName = interner.intern("kk_builder_list_addAll")
        kkBuilderSetAddName = interner.intern("kk_builder_set_add")
        kkBuilderSetAddAllName = interner.intern("kk_builder_set_addAll")
        kkBuilderMapPutName = interner.intern("kk_builder_map_put")
        kkMutableSetAddName = interner.intern("kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("kk_mutable_set_remove")
        builderDSLNames = [
            buildListName,
            buildSetName,
            buildMapName,
        ]
    }
}
