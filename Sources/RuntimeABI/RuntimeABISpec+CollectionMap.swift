private let abi = RuntimeABISectionBuilder("Collection")

public extension RuntimeABISpec {
    static let mapForEachSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("forEach", arity: 1, fallback: "kk_map_forEach"), "mapRaw fnPtr closureRaw outThrown")
    static let mapMapSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("map", arity: 1, fallback: "kk_map_map"), "mapRaw fnPtr closureRaw outThrown")
    static let mapMapNotNullSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("mapNotNull", arity: 1, fallback: "kk_map_mapNotNull"), "mapRaw fnPtr closureRaw outThrown")
    static let mapFilterSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("filter", arity: 1, fallback: "kk_map_filter"), "mapRaw fnPtr closureRaw outThrown")
    static let mapFilterNotSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("filterNot", arity: 1, fallback: "kk_map_filterNot"), "mapRaw fnPtr closureRaw outThrown")
    static let mapFilterKeysSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("filterKeys", arity: 1, fallback: "kk_map_filterKeys"), "mapRaw fnPtr closureRaw outThrown")
    static let mapFilterValuesSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("filterValues", arity: 1, fallback: "kk_map_filterValues"), "mapRaw fnPtr closureRaw outThrown")
    static let mapMapValuesSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("mapValues", arity: 1, fallback: "kk_map_mapValues"), "mapRaw fnPtr closureRaw outThrown")
    static let mapMapKeysSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("mapKeys", arity: 1, fallback: "kk_map_mapKeys"), "mapRaw fnPtr closureRaw outThrown")
    static let mapMapKeysToSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("mapKeysTo", arity: 2, fallback: "kk_map_mapKeysTo"), "mapRaw destRaw fnPtr closureRaw outThrown")
    static let mapMapValuesToSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("mapValuesTo", arity: 2, fallback: "kk_map_mapValuesTo"), "mapRaw destRaw fnPtr closureRaw outThrown")
    static let mapCountSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("count", arity: 1, fallback: "kk_map_count"), "mapRaw fnPtr closureRaw outThrown")
    static let mapAnySpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("any", arity: 1, fallback: "kk_map_any"), "mapRaw fnPtr closureRaw outThrown")
    static let mapAllSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("all", arity: 1, fallback: "kk_map_all"), "mapRaw fnPtr closureRaw outThrown")
    static let mapNoneSpec: RuntimeABIFunctionSpec = abi.th(stdlibMapHOFName("none", arity: 1, fallback: "kk_map_none"), "mapRaw fnPtr closureRaw outThrown")
    static let mapPlusSpec: RuntimeABIFunctionSpec = abi.nt("kk_map_plus", "mapRaw pairRaw")
    static let mapMinusSpec: RuntimeABIFunctionSpec = abi.nt("kk_map_minus", "mapRaw key")
    static let bridgeMapIteratorNextSpec: RuntimeABIFunctionSpec = abi.th("__kk_map_iterator_next", "iterRaw outThrown")
    static let bridgeMutableMapIteratorNextSpec: RuntimeABIFunctionSpec = abi.th("__kk_mutable_map_iterator_next", "iterRaw outThrown")

    private static func stdlibMapHOFName(_ memberName: String, arity: Int, fallback: String) -> String {
        StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .map,
            memberName: memberName,
            arity: arity,
            fallback: fallback
        )
    }

    static let collectionMapFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_map_of", "keysArrayRaw valuesArrayRaw count"),
        abi.nt("__kk_hash_map_of", "keysArrayRaw valuesArrayRaw count"),
        // Nominal-tag bridge for the LinkedHashMap constructor family
        // and linkedMapOf, mirroring `__kk_linked_hash_set_of`.
        abi.nt("__kk_linked_hash_map_of", "keysArrayRaw valuesArrayRaw count"),
        abi.nt("__kk_map_of_pairs", "pairsArrayRaw count"),
        abi.nt("__kk_hash_map_of_pairs", "pairsArrayRaw count"),
        abi.nt("__kk_linked_hash_map_of_pairs", "pairsArrayRaw count"),
        abi.th("__kk_emptyMap"),
        abi.nt("__kk_identity_hash_map_init", "mapRaw"),
        abi.nt("__kk_hash_map_storage", "mapRaw"),
        abi.nt("__kk_map_size", "mapRaw"),
        abi.nt("__kk_map_get", "mapRaw key"),
        abi.nt("__kk_map_contains_key", "mapRaw key", raw: true),
        abi.nt("__kk_map_contains_value", "mapRaw value", raw: true),
        abi.nt("__kk_map_is_empty", "mapRaw", raw: true),
        mapForEachSpec,
        mapMapSpec,
        mapMapNotNullSpec,
        mapFilterSpec,
        mapFilterNotSpec,
        abi.nt("__kk_map_withDefault", "mapRaw fnPtr closureRaw"),
        abi.th("__kk_map_implicit_default", "mapRaw key outThrown"),
        abi.nt("__kk_map_has_default", "mapRaw"),
        mapFilterKeysSpec,
        mapFilterValuesSpec,
        mapMapValuesSpec,
        mapMapKeysSpec,
        mapMapKeysToSpec,
        mapMapValuesToSpec,
        abi.nt("__kk_map_entries", "mapRaw"),
        abi.nt("__kk_map_keys", "mapRaw"),
        abi.nt("__kk_map_values", "mapRaw"),
        abi.nt("__kk_map_to_string", "mapRaw", ret: .opaquePointer),
        mapCountSpec,
        mapAnySpec,
        mapAllSpec,
        mapNoneSpec,
        mapPlusSpec,
        mapMinusSpec,
        abi.nt("__kk_map_iterator", "mapRaw"),
        abi.nt("__kk_map_iterator_hasNext", "iterRaw"),
        bridgeMapIteratorNextSpec,
        abi.nt("__kk_mutable_map_iterator", "mapRaw"),
        abi.nt("__kk_mutable_map_iterator_hasNext", "iterRaw"),
        bridgeMutableMapIteratorNextSpec,
        abi.th("__kk_mutable_map_iterator_remove", "iterRaw outThrown"),
    ]
}
