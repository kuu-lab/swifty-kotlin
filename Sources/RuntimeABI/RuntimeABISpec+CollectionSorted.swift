/// java.util sorted collection (TreeSet/TreeMap, Sorted/Navigable Set/Map) ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let collectionSortedFunctions: [RuntimeABIFunctionSpec] = [
        // KUU-1361: java.util sorted collections (TreeSet/TreeMap and the
        // SortedSet/NavigableSet/SortedMap/NavigableMap member surface).
        RuntimeABIFunctionSpec(
            name: "__kk_tree_set_new",
            parameters: [
                RuntimeABIParameter(name: "comparatorRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_set_new_collection",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_set_new_sorted_set",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_set_init",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "comparatorRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_comparator",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_first",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_last",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_lower",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_floor",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_ceiling",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_higher",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_poll_first",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_poll_last",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_descending",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_set_descending_iterator",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_map_new",
            parameters: [
                RuntimeABIParameter(name: "comparatorRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_map_new_map",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_map_new_sorted_map",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_tree_map_init",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "comparatorRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_comparator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_first_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_last_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_lower_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_floor_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_ceiling_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_higher_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_first_entry",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_last_entry",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_poll_first_entry",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_poll_last_entry",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_descending",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_sorted_map_descending_key_set",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
    ]
}
