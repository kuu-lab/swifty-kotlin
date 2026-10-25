private let abi = RuntimeABISectionBuilder("Collection")

public extension RuntimeABISpec {
    private static let listZipTransformParams = [
        RuntimeABIParameter(name: "listRaw", type: .intptr),
        RuntimeABIParameter(name: "otherRaw", type: .intptr),
        RuntimeABIParameter(name: "fnPtr", type: .intptr),
        RuntimeABIParameter(name: "closureRaw", type: .intptr),
        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
    ]

    static let listSortedBySpec = hofSpec("kk_list_sortedBy")

    static let listZipTransformSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_list_zip_transform",
        parameters: listZipTransformParams,
        returnType: .intptr,
        section: "Collection"
    )

    static let listTakeWhileSpec: RuntimeABIFunctionSpec = hofSpec("kk_list_takeWhile")

    static let listTakeLastWhileSpec: RuntimeABIFunctionSpec = hofSpec("kk_list_takeLastWhile")

    static let listDropWhileSpec: RuntimeABIFunctionSpec = hofSpec("kk_list_dropWhile")

    static let listDropLastWhileSpec: RuntimeABIFunctionSpec = hofSpec("kk_list_dropLastWhile")

    static let listMaxOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxOrNull", "listRaw")
    static let listMinOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_minOrNull", "listRaw")
    static let listMaxSpec: RuntimeABIFunctionSpec = abi.th("kk_list_max", "listRaw outThrown")
    static let listMinSpec: RuntimeABIFunctionSpec = abi.th("kk_list_min", "listRaw outThrown")
    static let listSortedSpec: RuntimeABIFunctionSpec = abi.nt("kk_list_sorted", "listRaw")
    static let listSortedPrimitiveSpec: RuntimeABIFunctionSpec = abi.th("kk_list_sorted_primitive", "listRaw kindRaw:int32")
    static let listShuffledSpec: RuntimeABIFunctionSpec = abi.nt("kk_list_shuffled", "listRaw")
    static let listShuffledRandomSpec: RuntimeABIFunctionSpec = abi.nt("kk_list_shuffled_random", "listRaw randomRaw")
    static let listSortedByPrimitiveSpec: RuntimeABIFunctionSpec = abi.th("kk_list_sortedBy_primitive", "listRaw fnPtr closureRaw kindRaw:int32 outThrown")
    static let listSortedDescendingSpec: RuntimeABIFunctionSpec = abi.nt("kk_list_sortedDescending", "listRaw")
    static let listSortedDescendingPrimitiveSpec: RuntimeABIFunctionSpec = abi.th("kk_list_sortedDescending_primitive", "listRaw kindRaw:int32")

    static let listSortedByDescendingSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_list_sortedByDescending",
        parameters: hofLambdaParams,
        returnType: .intptr,
        section: "Collection"
    )

    static let listSortedByDescendingPrimitiveSpec: RuntimeABIFunctionSpec = abi.th("kk_list_sortedByDescending_primitive", "listRaw fnPtr closureRaw kindRaw:int32 outThrown")

    static let listSortedWithSpec: RuntimeABIFunctionSpec = hofSpec("kk_list_sortedWith")

    static let listMaxBySpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxBy", "listRaw fnPtr closureRaw outThrown")
    static let listMaxByOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxByOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinByOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_minByOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinBySpec: RuntimeABIFunctionSpec = abi.th("kk_list_minBy", "listRaw fnPtr closureRaw outThrown")
    static let listMaxOfOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxOfOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinOfOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_minOfOrNull", "listRaw fnPtr closureRaw outThrown")

    static let hofLambdaParams: [RuntimeABIParameter] = [
        RuntimeABIParameter(name: "listRaw", type: .intptr),
        RuntimeABIParameter(name: "fnPtr", type: .intptr),
        RuntimeABIParameter(name: "closureRaw", type: .intptr),
        RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
    ]

    static func hofSpec(_ name: String) -> RuntimeABIFunctionSpec {
        RuntimeABIFunctionSpec(
            name: name, parameters: hofLambdaParams,
            returnType: .intptr, section: "Collection"
        )
    }

    static let collectionHOFFunctions: [RuntimeABIFunctionSpec] = {
        func iterableSpec(_ name: String, parameters: [RuntimeABIParameter]) -> RuntimeABIFunctionSpec {
            RuntimeABIFunctionSpec(
                name: name,
                parameters: parameters,
                returnType: .intptr,
                section: "Collection"
            )
        }
        let iterableLambdaParams = [
            RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let iterableOutThrownParams = [
            RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]

        let listWindowChunkReceiverSizeParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listWindowChunkReceiverSizeLambdaParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listWindowedParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "step", type: .intptr),
            RuntimeABIParameter(name: "partialWindows", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listWindowedTransformParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "size", type: .intptr),
            RuntimeABIParameter(name: "step", type: .intptr),
            RuntimeABIParameter(name: "partialWindows", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ]
        let listZipParams = [
            RuntimeABIParameter(name: "listRaw", type: .intptr),
            RuntimeABIParameter(name: "otherRaw", type: .intptr),
        ]
        let listWindowChunkBridgeSpecs = [
            RuntimeABIFunctionSpec(
                name: "__kk_list_chunked",
                parameters: listWindowChunkReceiverSizeParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_chunked_transform",
                parameters: listWindowChunkReceiverSizeLambdaParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_windowed",
                parameters: listWindowedParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_windowed_transform",
                parameters: listWindowedTransformParams,
                returnType: .intptr,
                section: "Collection"
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zip",
                parameters: listZipParams,
                returnType: .intptr,
                section: "Collection",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_list_zip_transform",
                parameters: listZipTransformParams,
                returnType: .intptr,
                section: "Collection"
            ),
            abi.nt("__kk_list_zipWithNext", "listRaw"),
            abi.th("__kk_list_zipWithNextTransform", "listRaw fnPtr closureRaw outThrown"),
        ]
        let asReversedSpec = abi.nt("__kk_list_as_reversed", "listRaw")
        let mutableAsReversedSpec = abi.nt("__kk_mutable_list_as_reversed", "listRaw")
        let listSliceTakeDropSpecs = [
            abi.th("kk_list_take", "listRaw count outThrown"),
            abi.th("kk_list_takeLast", "listRaw count outThrown"),
            abi.th("kk_list_drop", "listRaw count outThrown"),
            abi.nt("kk_list_dropLast", "listRaw count"),
            listTakeWhileSpec,
            listTakeLastWhileSpec,
            listDropWhileSpec,
            listDropLastWhileSpec,
        ]
        let randomSpec = abi.th("kk_list_random", "listRaw outThrown")
        let randomOrNullSpec = abi.nt("kk_list_randomOrNull", "listRaw")
        return [
            hofSpec("kk_list_forEach"),
            iterableSpec("__kk_iterable_requireNoNulls", parameters: iterableOutThrownParams),
            iterableSpec("__kk_iterable_firstNotNullOf", parameters: iterableLambdaParams),
            iterableSpec("__kk_iterable_firstNotNullOfOrNull", parameters: iterableLambdaParams),
            iterableSpec("__kk_iterable_all", parameters: iterableLambdaParams),
            iterableSpec("__kk_iterable_any", parameters: iterableLambdaParams),
            iterableSpec("__kk_iterable_last", parameters: iterableOutThrownParams),
            listSortedBySpec,
            listSortedByPrimitiveSpec,
            listZipTransformSpec,
        ]
            + listWindowChunkBridgeSpecs
            + [
                asReversedSpec, mutableAsReversedSpec,
                listMaxOrNullSpec, listMinOrNullSpec,
                listMaxSpec, listMinSpec,
                listSortedSpec,
                listSortedPrimitiveSpec,
                listShuffledSpec, listShuffledRandomSpec, randomSpec, randomOrNullSpec,
            ]
            + listSliceTakeDropSpecs
            + [

                listSortedDescendingSpec,
                listSortedDescendingPrimitiveSpec,
                listSortedByDescendingSpec,
                listSortedByDescendingPrimitiveSpec,
                listSortedWithSpec,
                listMaxBySpec,
                listMaxByOrNullSpec,
                listMinByOrNullSpec,
                listMinBySpec,
                listMaxOfOrNullSpec,
                listMinOfOrNullSpec,
                abi.nt("__kk_arraydeque_new"),
                abi.th("__kk_arraydeque_new_with_capacity", "capacity outThrown"),
                abi.nt("__kk_arraydeque_new_from_collection", "collectionRaw"),
                abi.nt("__kk_arraydeque_addFirst", "dequeRaw element"),
                abi.nt("__kk_arraydeque_addLast", "dequeRaw element"),
                abi.nt("__kk_arraydeque_removeFirst", "dequeRaw"),
                abi.nt("__kk_arraydeque_removeLast", "dequeRaw"),
                abi.nt("__kk_arraydeque_get", "dequeRaw index"),
                abi.nt("__kk_arraydeque_size", "dequeRaw"),
                abi.nt("__kk_auto_closeable_create", "fnPtr closureRaw"),
            ]
    }()
}
