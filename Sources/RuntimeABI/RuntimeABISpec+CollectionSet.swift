private let abi = RuntimeABISectionBuilder("Collection")
private let abiEnum = RuntimeABISectionBuilder("Enum")

public extension RuntimeABISpec {
    static let collectionSetFunctions: [RuntimeABIFunctionSpec] = [
        abiEnum.nt("__kk_enum_set_class", "classRaw"),
        abiEnum.nt("__kk_enum_set_values", "classRaw"),
        abi.nt("__kk_set_of", "arrayRaw count"),
        abi.nt("__kk_hash_set_of", "arrayRaw count"),
        abi.th("__kk_hash_set_new_checked", "capacity loadFactorBits outThrown"),
        // Nominal-tag bridge for the mutable set factories and the
        // LinkedHashSet constructors, mirroring `__kk_hash_set_of`.
        abi.nt("__kk_linked_hash_set_of", "arrayRaw count"),
        abi.th("__kk_emptySet"),
        // Attach runtime-backed storage to source-allocated
        // LinkedHashSet instances, including user subclasses.
        abi.nt("__kk_linked_hash_set_init", "setRaw"),
        abi.nt("__kk_set_size", "setRaw"),
        abi.nt("__kk_set_contains", "setRaw element", raw: true),
        abi.nt("__kk_set_is_empty", "setRaw", raw: true),
        abi.nt("__kk_set_to_string", "setRaw", ret: .opaquePointer),
        abi.th("__kk_collection_toList", "collRaw"),
        abi.nt("__kk_collection_toMutableList", "collRaw"),
        abi.nt("__kk_array_list_of", "arrayRaw count"),
        abi.th("__kk_array_list_new_checked", "initialCapacity outThrown"),
        abi.nt("__kk_array_list_init", "listRaw"),
        abi.nt("__kk_collection_toArrayList", "collRaw"),
        abi.th("__kk_collection_toTypedArray", "collRaw"),
        abi.nt("__kk_iterable_toMutableSet", "iterableRaw"),
        abi.nt("__kk_iterable_toHashSet", "iterableRaw"),
        abi.nt("__kk_collection_toCollection", "collRaw destRaw"),
        abi.nt("__kk_collection_size", "collRaw"),
        abi.nt("__kk_collection_isEmpty", "collRaw"),
        abi.nt("__kk_collection_containsAll", "collRaw elementsRaw"),
    ]
}
