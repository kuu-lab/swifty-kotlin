/// Set, LinkedHashSet, and toMutableList/toMutableSet ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let collectionSetFunctions: [RuntimeABIFunctionSpec] = [
        // Set
        RuntimeABIFunctionSpec(
            name: "__kk_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_hash_set_new_checked",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
                RuntimeABIParameter(name: "loadFactorBits", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        // BUG-254: nominal-tag bridge for the mutable set factories and the
        // LinkedHashSet constructors, mirroring `__kk_hash_set_of`.
        RuntimeABIFunctionSpec(
            name: "__kk_linked_hash_set_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptySet
        RuntimeABIFunctionSpec(
            name: "__kk_emptySet",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        // BUG-196: Attach runtime-backed storage to source-allocated
        // LinkedHashSet instances, including user subclasses.
        RuntimeABIFunctionSpec(
            name: "__kk_linked_hash_set_init",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_size",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_contains",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_is_empty",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_set_to_string",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-021: Collection<T>.toMutableList()
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_list_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_list_new_checked",
            parameters: [
                RuntimeABIParameter(name: "initialCapacity", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_list_init",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toArrayList",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toTypedArray",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // STDLIB-021: Iterable<T>.toMutableSet()
        RuntimeABIFunctionSpec(
            name: "__kk_iterable_toMutableSet",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_iterable_toHashSet",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_toCollection",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_size",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_collection_containsAll",
            parameters: [
                RuntimeABIParameter(name: "collRaw", type: .intptr),
                RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
    ]
}
