import RuntimeABI

/// BuilderDSL lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct BuilderDSLLookupNames {
    // Builder DSL names (STDLIB-002)
    let buildMapName: InternedString
    let kkBuildMapName: InternedString
    let kkBuildMapWithCapacityName: InternedString
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        buildMapName = interner.intern("buildMap")
        kkBuildMapName = interner.intern("__kk_build_map")
        kkBuildMapWithCapacityName = interner.intern("__kk_build_map_with_capacity")
        kkMutableSetAddName = interner.intern("__kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("__kk_mutable_set_remove")
        builderDSLNames = [
            buildMapName,
        ]
    }
}
