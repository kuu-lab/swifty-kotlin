/// Mutable-collection mutation bridge ABI specs split out from `RuntimeABISpec+Collection.swift`.
public extension RuntimeABISpec {
    static let bridgeMutableListAddSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_add",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionAddThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_add_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionRemoveThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_remove_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionClearThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_clear_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionRemoveAllThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_removeAll_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionRetainAllThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_retainAll_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionAddAllThrowingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_addAll_throwing",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elementsRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableCollectionAddSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_add",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: false
    )

    static let bridgeMutableListRemoveSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_remove",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: false
    )

    static let bridgeMutableListRemoveDispatchSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_remove_dispatch",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: true
    )

    static let bridgeMutableCollectionAddAllSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_collection_addAll",
        parameters: [
            RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            RuntimeABIParameter(name: "elementsRaw", type: .intptr),
        ],
        returnType: .intptr,
        section: "Collection",
        isThrowing: false
    )

    static let bridgeMutableListRemoveAtSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_removeAt",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "index", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableListAddAtSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_add_at",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "index", type: .intptr),
            RuntimeABIParameter(name: "element", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableListSetSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_list_set",
        parameters: [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "index", type: .intptr),
            RuntimeABIParameter(name: "element", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableSetAddSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_set_add",
        parameters: [
            RuntimeABIParameter(name: "setRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection",
        returnsRawBoolean: true
    )

    static let bridgeMutableSetRemoveSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_set_remove",
        parameters: [
            RuntimeABIParameter(name: "setRaw", type: .intptr),
            RuntimeABIParameter(name: "elem", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection",
        returnsRawBoolean: true
    )

    static let bridgeMutableSetClearSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_set_clear",
        parameters: [
            RuntimeABIParameter(name: "setRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableMapPutSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_map_put",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "key", type: .intptr),
            RuntimeABIParameter(name: "value", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableMapRemoveSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_map_remove",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "key", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableMapClearSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_map_clear",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )

    static let bridgeMutableMapPutAllSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "__kk_mutable_map_putAll",
        parameters: [
            RuntimeABIParameter(name: "mapRaw", type: .intptr),
            RuntimeABIParameter(name: "entriesRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "Collection"
    )
}
