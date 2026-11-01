private let abi = RuntimeABISectionBuilder("Collection")
private let abiEnum = RuntimeABISectionBuilder("Enum")

public extension RuntimeABISpec {
    static let bridgeListGetSpec: RuntimeABIFunctionSpec = abi.th("__kk_list_get", "listRaw index outThrown")
    static let listIteratorNextSpec: RuntimeABIFunctionSpec = abi.th("kk_list_iterator_next", "iterRaw outThrown")
    static let indexingIterableNextSpec: RuntimeABIFunctionSpec = abi.th("kk_indexing_iterable_next", "iterRaw outThrown")

    static let collectionFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_objects_equals", "lhs rhs outThrown"),
        abi.nt("__kk_values_equal", "lhs rhs"),
        abi.th("__kk_list_check_modification", "listRaw outThrown"),
        abi.nt("__kk_list_of", "arrayRaw count"),
        abi.nt("__kk_singleton_list_of", "element"),
        abi.th("__kk_emptyList"),
        abi.nt("__kk_array_list_is_read_only", "listRaw"),
        abi.nt("__kk_list_size", "listRaw"),
        bridgeListGetSpec,
        abi.th("__kk_list_index_of", "listRaw element outThrown"),
        abi.th("__kk_list_lastIndexOf", "listRaw element outThrown"),
        abiEnum.th("__kk_enum_entries_get", "listRaw index outThrown"),
    ]
    + [
        abi.nt("kk_list_is_empty", "listRaw"),
        abi.nt("kk_list_iterator", "listRaw"),
        abi.nt("kk_list_iterator_hasNext", "iterRaw"),
        abi.nt("__kk_mutable_list_listIterator", "listRaw"),
        // KUU-3963: same erased shape as `kk_list_iterator`; the read-only
        // zero-arg `listIterator()` bridge re-resolves the reflected JVM
        // class (`ListItr` family) on the iterator it returns.
        abi.nt("__kk_list_listIterator", "listRaw"),
        listIteratorNextSpec,
        // IndexingIterable is the iterator bridge retained by List.withIndex().
        abi.nt("kk_indexing_iterable_iterator", "iterableRaw"),
        abi.nt("kk_indexing_iterable_hasNext", "iterRaw"),
        indexingIterableNextSpec,
        abi.th("kk_list_iterator_at", "listRaw index outThrown"),
        abi.th("kk_list_subList", "listRaw fromIndex toIndex outThrown"),
        abi.th("kk_list_iterator_hasPrevious", "iterRaw"),
        abi.th("kk_list_iterator_previous", "iterRaw"),
        abi.nt("kk_list_iterator_nextIndex", "iterRaw"),
        abi.nt("kk_list_iterator_previousIndex", "iterRaw"),
        abi.nt("kk_list_to_string", "listRaw", ret: .opaquePointer),
    ] + collectionSetFunctions
        + Self.collectionHOFFunctions
        + collectionMapFunctions
        + collectionArrayFunctions
        + collectionTupleFunctions
        + collectionBuilderFunctions
        + collectionSortedFunctions
}
