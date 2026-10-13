/// Builder DSL ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let collectionBuilderFunctions: [RuntimeABIFunctionSpec] = [
        // Builder DSL (STDLIB-002)
        // `__kk_build_list` / `__kk_build_list_with_capacity` were removed with
        // their lowering rewrite (RF-LOWER-CALL-004); `buildList` is served by
        // `CollectionBuilders.kt` via `__kk_builder_list_*`.
        RuntimeABIFunctionSpec(
            name: "__kk_builder_list_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_set_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_map_new",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_list_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_set_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_builder_map_freeze",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeMutableListAddSpec,
        bridgeMutableCollectionAddThrowingSpec,
        bridgeMutableCollectionRemoveThrowingSpec,
        bridgeMutableCollectionClearThrowingSpec,
        bridgeMutableCollectionRemoveAllThrowingSpec,
        bridgeMutableCollectionRetainAllThrowingSpec,
        bridgeMutableCollectionAddAllThrowingSpec,
        bridgeMutableCollectionAddSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_add_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "argument", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "argument", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_remove_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "argument", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_clear_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeAll_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "argument", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_retainAll_checked",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
                RuntimeABIParameter(name: "argument", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        bridgeMutableListRemoveSpec,
        bridgeMutableListRemoveDispatchSpec,
        bridgeMutableCollectionAddAllSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_collection_addAll_iterable",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_retainAll",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeMutableListRemoveAtSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeFirst",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeFirstOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeLast",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_removeLastOrNull",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_clear",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        bridgeMutableListAddAtSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_list_addAll_at",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        bridgeMutableListSetSpec,
        bridgeMutableSetAddSpec,
        bridgeMutableSetRemoveSpec,
        bridgeMutableSetClearSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll_sequence",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "sequenceRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_addAll_iterable",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_removeAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_set_retainAll",
            parameters: [
                RuntimeABIParameter(name: "setRaw", type: .intptr),
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection",
            returnsRawBoolean: true
        ),
        bridgeMutableMapPutSpec,
        bridgeMutableMapRemoveSpec,
        bridgeMutableMapClearSpec,
        bridgeMutableMapPutAllSpec,
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_plusAssign_pair",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "pairRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_mutable_map_withDefault",
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
            name: "__kk_mutable_map_entry_setValue",
            parameters: [
                RuntimeABIParameter(name: "entryRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
    ]
}
