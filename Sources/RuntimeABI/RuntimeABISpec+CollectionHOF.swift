private let abi = RuntimeABISectionBuilder("Collection")

public extension RuntimeABISpec {
    static let listSortedBySpec = abi.th("kk_list_sortedBy", "listRaw fnPtr closureRaw outThrown")

    static let listZipTransformSpec = abi.th("kk_list_zip_transform", "listRaw otherRaw fnPtr closureRaw outThrown")

    static let listTakeWhileSpec = abi.th("kk_list_takeWhile", "listRaw fnPtr closureRaw outThrown")

    static let listTakeLastWhileSpec = abi.th("kk_list_takeLastWhile", "listRaw fnPtr closureRaw outThrown")

    static let listDropWhileSpec = abi.th("kk_list_dropWhile", "listRaw fnPtr closureRaw outThrown")

    static let listDropLastWhileSpec = abi.th("kk_list_dropLastWhile", "listRaw fnPtr closureRaw outThrown")

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

    static let listSortedByDescendingSpec = abi.th("kk_list_sortedByDescending", "listRaw fnPtr closureRaw outThrown")

    static let listSortedByDescendingPrimitiveSpec: RuntimeABIFunctionSpec = abi.th("kk_list_sortedByDescending_primitive", "listRaw fnPtr closureRaw kindRaw:int32 outThrown")

    static let listSortedWithSpec = abi.th("kk_list_sortedWith", "listRaw fnPtr closureRaw outThrown")

    static let listMaxBySpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxBy", "listRaw fnPtr closureRaw outThrown")
    static let listMaxByOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxByOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinByOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_minByOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinBySpec: RuntimeABIFunctionSpec = abi.th("kk_list_minBy", "listRaw fnPtr closureRaw outThrown")
    static let listMaxOfOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_maxOfOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinOfOrNullSpec: RuntimeABIFunctionSpec = abi.th("kk_list_minOfOrNull", "listRaw fnPtr closureRaw outThrown")

    static let collectionHOFFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("kk_list_forEach", "listRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_iterable_requireNoNulls", "iterableRaw outThrown"),
        abi.th("__kk_iterable_firstNotNullOf", "iterableRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_iterable_firstNotNullOfOrNull", "iterableRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_iterable_all", "iterableRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_iterable_any", "iterableRaw fnPtr closureRaw outThrown"),
        abi.th("__kk_iterable_last", "iterableRaw outThrown"),
        listSortedBySpec,
        listSortedByPrimitiveSpec,
        listZipTransformSpec,
        abi.th("__kk_list_chunked", "listRaw size outThrown"),
        abi.th("__kk_list_chunked_transform", "listRaw size fnPtr closureRaw outThrown"),
        abi.th("__kk_list_windowed", "listRaw size step partialWindows outThrown"),
        abi.th("__kk_list_windowed_transform", "listRaw size step partialWindows fnPtr closureRaw outThrown"),
        abi.nt("__kk_list_zip", "listRaw otherRaw"),
        abi.th("__kk_list_zip_transform", "listRaw otherRaw fnPtr closureRaw outThrown"),
        abi.nt("__kk_list_zipWithNext", "listRaw"),
        abi.th("__kk_list_zipWithNextTransform", "listRaw fnPtr closureRaw outThrown"),
        abi.nt("__kk_list_as_reversed", "listRaw"),
        abi.nt("__kk_mutable_list_as_reversed", "listRaw"),
        listMaxOrNullSpec, listMinOrNullSpec,
        listMaxSpec, listMinSpec,
        listSortedSpec,
        listSortedPrimitiveSpec,
        listShuffledSpec, listShuffledRandomSpec, abi.th("kk_list_random", "listRaw outThrown"), abi.nt("kk_list_randomOrNull", "listRaw"),
        abi.th("kk_list_take", "listRaw count outThrown"),
        abi.th("kk_list_takeLast", "listRaw count outThrown"),
        abi.th("kk_list_drop", "listRaw count outThrown"),
        abi.nt("kk_list_dropLast", "listRaw count"),
        listTakeWhileSpec,
        listTakeLastWhileSpec,
        listDropWhileSpec,
        listDropLastWhileSpec,
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
        abi.nt("__kk_closeable_create", "fnPtr closureRaw"),
    ]
}
