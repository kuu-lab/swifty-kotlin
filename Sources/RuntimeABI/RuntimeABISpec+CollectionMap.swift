/// Map HOF, map operator, and map iterator ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let mapForEachSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("forEach", arity: 1, fallback: "kk_map_forEach"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("map", arity: 1, fallback: "kk_map_map"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapNotNullSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("mapNotNull", arity: 1, fallback: "kk_map_mapNotNull"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapFilterSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("filter", arity: 1, fallback: "kk_map_filter"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapFilterNotSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("filterNot", arity: 1, fallback: "kk_map_filterNot"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapFilterKeysSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("filterKeys", arity: 1, fallback: "kk_map_filterKeys"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapFilterValuesSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("filterValues", arity: 1, fallback: "kk_map_filterValues"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapValuesSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("mapValues", arity: 1, fallback: "kk_map_mapValues"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapKeysSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("mapKeys", arity: 1, fallback: "kk_map_mapKeys"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapKeysToSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("mapKeysTo", arity: 2, fallback: "kk_map_mapKeysTo"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "destRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapMapValuesToSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("mapValuesTo", arity: 2, fallback: "kk_map_mapValuesTo"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "destRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapCountSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("count", arity: 1, fallback: "kk_map_count"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapAnySpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("any", arity: 1, fallback: "kk_map_any"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapAllSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("all", arity: 1, fallback: "kk_map_all"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapNoneSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: stdlibMapHOFName("none", arity: 1, fallback: "kk_map_none"),
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let mapPlusSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_map_plus",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "pairRaw", type: .intptr),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: false
    )

    static let mapMinusSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_map_minus",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "key", type: .intptr),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: false
    )

    static let bridgeMapIteratorNextSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_map_iterator_next",
        parameters: [
            RuntimeABIParameter(name: "iterRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableMapIteratorNextSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_map_iterator_next",
        parameters: [
            RuntimeABIParameter(name: "iterRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    private static func stdlibMapHOFName(_ memberName: String, arity: Int, fallback: String) -> String {
        StdlibSurfaceSpec.collectionHOFRuntimeLinkName(
            ownerKind: .map,
            memberName: memberName,
            arity: arity,
            fallback: fallback
        )
    }

    static let collectionMapFunctions: [RuntimeABIFunctionSpec] = [
        // Map
        RuntimeABIFunctionSpec(
            name: "__kk_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // KUU-556: nominal-tag bridge for the LinkedHashMap constructor family
        // and linkedMapOf, mirroring `__kk_linked_hash_set_of`.
        RuntimeABIFunctionSpec(
            name: "__kk_linked_hash_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_of_pairs",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_map_of_pairs",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_linked_hash_map_of_pairs",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptyMap
        RuntimeABIFunctionSpec(
            name: "__kk_emptyMap",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_size",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_get",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_is_empty",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        mapForEachSpec,
        mapMapSpec,
        mapMapNotNullSpec,
        mapFilterSpec,
        mapFilterNotSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_map_withDefault",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_implicit_default",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_has_default",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        mapFilterKeysSpec,
        mapFilterValuesSpec,
        mapMapValuesSpec,
        mapMapKeysSpec,
        mapMapKeysToSpec,
        mapMapValuesToSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_map_entries",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_keys",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_values",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_to_string",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
        mapCountSpec,
        mapAnySpec,
        mapAllSpec,
        mapNoneSpec,
        mapPlusSpec,
        mapMinusSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeMapIteratorNextSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeMutableMapIteratorNextSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_iterator_remove",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
    ]
}
