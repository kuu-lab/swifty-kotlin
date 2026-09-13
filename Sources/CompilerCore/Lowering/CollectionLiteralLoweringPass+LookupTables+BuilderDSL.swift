import RuntimeABI

/// BuilderDSL lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
/// `builderDSLNames` is deliberately empty: RF-LOWER-CALL-004 / -005 / -006
/// removed the `buildList` / `buildSet` / `buildMap` rewrites, so no callee
/// should be routed to a `__kk_build_*` helper any more.  Retiring this struct
/// and `isStdlibBuilderDSLCall` is RF-LOWER-CALL-015; `kkMutableSet*` are
/// non-builder names used by `+CallRewriteCollectionMember.swift` and only live
/// here by co-location.
struct BuilderDSLLookupNames {
    let kkMutableSetAddName: InternedString
    let kkMutableSetRemoveName: InternedString
    let builderDSLNames: Set<InternedString>

    init(interner: StringInterner) {
        kkMutableSetAddName = interner.intern("__kk_mutable_set_add")
        kkMutableSetRemoveName = interner.intern("__kk_mutable_set_remove")
        builderDSLNames = []
    }
}
