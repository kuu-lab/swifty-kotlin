public extension RuntimeABISpec {
    static let bridgeListGetSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_list_get",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "index", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let listIteratorNextSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_list_iterator_next",
        parameters: [
            RuntimeABIParameter(name: "iterRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let indexingIterableNextSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_indexing_iterable_next",
        parameters: [
            RuntimeABIParameter(name: "iterRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let collectionFunctions: [RuntimeABIFunctionSpec] = [
        // Core helpers
        RuntimeABIFunctionSpec(
            name: "__kk_values_equal",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // List
        RuntimeABIFunctionSpec(
            name: "__kk_list_check_modification",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_list_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        // STDLIB-410: emptyList
        RuntimeABIFunctionSpec(
            name: "__kk_emptyList",
            parameters: [],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_list_is_read_only",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_list_size",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeListGetSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_enum_entries_get",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: true
        ),
    ]
    + [
        RuntimeABIFunctionSpec(
            name: "kk_list_is_empty",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_listIterator",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        listIteratorNextSpec,
        // IndexingIterable is the iterator bridge retained by List.withIndex().
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_iterator",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_indexing_iterable_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        indexingIterableNextSpec,
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_at",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_subList",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasPrevious",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_previous",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_nextIndex",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_previousIndex",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_string",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection",
            isThrowing: false
        ),
    ] + collectionSetFunctions
        + Self.collectionHOFFunctions
        + collectionMapFunctions
        + collectionArrayFunctions
        + collectionTupleFunctions
        + collectionBuilderFunctions
        + collectionSortedFunctions
}
