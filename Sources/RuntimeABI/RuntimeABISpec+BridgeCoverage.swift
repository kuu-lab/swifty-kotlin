private let collectionABI = RuntimeABISectionBuilder("Collection")
private let rangeABI = RuntimeABISectionBuilder("Range")
private let sequenceABI = RuntimeABISectionBuilder("Sequence")
private let charABI = RuntimeABISectionBuilder("Char")
private let numericConversionABI = RuntimeABISectionBuilder("NumericConversion")
private let operatorABI = RuntimeABISectionBuilder("Operator")
private let systemABI = RuntimeABISectionBuilder("System")
private let nativeABI = RuntimeABISectionBuilder("Native")
private let coroutineABI = RuntimeABISectionBuilder("Coroutine")
private let delegateABI = RuntimeABISectionBuilder("Delegate")

private let collectionBridgeBase: [RuntimeABIFunctionSpec] = [
    collectionABI.th("kk_iterable_iterator", "iterableRaw outThrown"),
]

private let listClosureBridgeFunctions = [
    RuntimeABISpec.listMaxOfSpec,
    RuntimeABISpec.listMaxWithSpec,
    RuntimeABISpec.listMaxWithOrNullSpec,
    RuntimeABISpec.listMinOfSpec,
    RuntimeABISpec.listMinWithSpec,
    RuntimeABISpec.listMinWithOrNullSpec,
]

private let listComparatorBridgeFunctions = [
    RuntimeABISpec.listMaxOfWithSpec,
    RuntimeABISpec.listMaxOfWithOrNullSpec,
    RuntimeABISpec.listMinOfWithSpec,
    RuntimeABISpec.listMinOfWithOrNullSpec,
]

private let mapBridgeFunctions = [
    RuntimeABISpec.mapFlatMapSpec,
    RuntimeABISpec.mapMaxByOrNullSpec,
    RuntimeABISpec.mapMinByOrNullSpec,
]

private let sequenceAndSetBridgeFunctions: [RuntimeABIFunctionSpec] = [
    rangeABI.nt("__kk_range_hasNext", "iterRaw"),
    rangeABI.th("__kk_range_iterator", "rangeRaw outThrown"),
    rangeABI.nt("__kk_range_next", "iterRaw"),
    rangeABI.nt("__kk_range_for_in_hasNext", "iterRaw"),
    rangeABI.nt("__kk_range_for_in_iterator", "rangeRaw"),
    rangeABI.nt("__kk_range_for_in_next", "iterRaw"),
    RuntimeABISpec.sequenceFilterNotSpec,
    collectionABI.nt("__kk_set_of_not_null", "arrayRaw count"),
    collectionABI.nt("__kk_set_of_not_null_single", "arrayRaw count"),
]

public extension RuntimeABISpec {
    static let listMaxOfSpec = collectionABI.th("kk_list_maxOf", "listRaw fnPtr closureRaw outThrown")
    static let listMaxWithSpec = collectionABI.th("kk_list_maxWith", "listRaw fnPtr closureRaw outThrown")
    static let listMaxWithOrNullSpec = collectionABI.th("kk_list_maxWithOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMinOfSpec = collectionABI.th("kk_list_minOf", "listRaw fnPtr closureRaw outThrown")
    static let listMinWithSpec = collectionABI.th("kk_list_minWith", "listRaw fnPtr closureRaw outThrown")
    static let listMinWithOrNullSpec = collectionABI.th("kk_list_minWithOrNull", "listRaw fnPtr closureRaw outThrown")
    static let listMaxOfWithSpec = collectionABI.th("kk_list_maxOfWith", "listRaw cmpFnPtr cmpClosureRaw selFnPtr selClosureRaw outThrown")
    static let listMaxOfWithOrNullSpec = collectionABI.th("kk_list_maxOfWithOrNull", "listRaw cmpFnPtr cmpClosureRaw selFnPtr selClosureRaw outThrown")
    static let listMinOfWithSpec = collectionABI.th("kk_list_minOfWith", "listRaw cmpFnPtr cmpClosureRaw selFnPtr selClosureRaw outThrown")
    static let listMinOfWithOrNullSpec = collectionABI.th("kk_list_minOfWithOrNull", "listRaw cmpFnPtr cmpClosureRaw selFnPtr selClosureRaw outThrown")
    static let mapFlatMapSpec = collectionABI.th("kk_map_flatMap", "mapRaw fnPtr closureRaw outThrown")
    static let mapMaxByOrNullSpec = collectionABI.th("kk_map_maxByOrNull", "mapRaw fnPtr closureRaw outThrown")
    static let mapMinByOrNullSpec = collectionABI.th("kk_map_minByOrNull", "mapRaw fnPtr closureRaw outThrown")

    static let sequenceFilterNotSpec: RuntimeABIFunctionSpec = sequenceABI.nt("kk_sequence_filterNot", "seqRaw fnPtr closureRaw")

    static let numericRuntimeBridgeFunctions: [RuntimeABIFunctionSpec] = [
        charABI.th("kk_char_category", "value"),
        charABI.th("kk_char_code", "value"),
        charABI.th("kk_char_directionality", "value"),
        charABI.th("kk_char_toDouble", "value"),
        charABI.th("kk_char_toDoubleOrNull", "value"),
        charABI.th("kk_char_toInt", "value"),
        charABI.th("kk_char_toIntOrNull", "value"),
        numericConversionABI.nt("__kk_double_toBits", "value"),
        numericConversionABI.nt("__kk_double_toRawBits", "value"),
        numericConversionABI.nt("__kk_double_fromBits", "bits"),
        numericConversionABI.nt("__kk_double_to_int", "value"),
        numericConversionABI.nt("__kk_double_to_long", "value"),
        numericConversionABI.nt("__kk_float_fromBits", "bits"),
        numericConversionABI.nt("__kk_float_toBits", "value"),
        numericConversionABI.nt("__kk_float_toRawBits", "value"),
        numericConversionABI.nt("__kk_float_to_double_bits", "value"),
        numericConversionABI.nt("__kk_float_to_int", "value"),
        numericConversionABI.nt("__kk_float_to_long", "value"),
        numericConversionABI.nt("kk_int_to_double_bits", "value"),
        numericConversionABI.nt("kk_int_to_float_bits", "value"),
        numericConversionABI.nt("kk_int_to_long", "value"),
        numericConversionABI.nt("kk_int_to_uint", "value"),
        numericConversionABI.nt("kk_int_to_ulong", "value"),
        numericConversionABI.nt("kk_long_to_uint", "value"),
        numericConversionABI.nt("kk_long_to_ulong", "value"),
        numericConversionABI.nt("kk_uint_to_int", "value"),
        numericConversionABI.nt("kk_uint_to_long", "value"),
        numericConversionABI.nt("kk_uint_to_ulong", "value"),
        numericConversionABI.nt("kk_ulong_to_int", "value"),
        numericConversionABI.nt("kk_ulong_to_long", "value"),
        operatorABI.nt("kk_double_equals", "lhs rhs"),
        operatorABI.nt("kk_op_dadd", "lhs rhs"),
        operatorABI.nt("kk_op_ddiv", "lhs rhs"),
        operatorABI.nt("kk_op_deq", "lhs rhs"),
        operatorABI.nt("kk_op_dge", "lhs rhs"),
        operatorABI.nt("kk_op_dgt", "lhs rhs"),
        operatorABI.nt("kk_op_dle", "lhs rhs"),
        operatorABI.nt("kk_op_dlt", "lhs rhs"),
        operatorABI.nt("kk_op_dmod", "lhs rhs"),
        operatorABI.nt("kk_op_dne", "lhs rhs"),
        operatorABI.nt("kk_op_dsub", "lhs rhs"),
        operatorABI.nt("kk_op_elvis", "lhs rhs"),
        operatorABI.nt("kk_float_equals", "lhs rhs"),
        operatorABI.nt("kk_op_fadd", "lhs rhs"),
        operatorABI.nt("kk_op_fdiv", "lhs rhs"),
        operatorABI.nt("kk_op_feq", "lhs rhs"),
        operatorABI.nt("kk_op_fge", "lhs rhs"),
        operatorABI.nt("kk_op_fgt", "lhs rhs"),
        operatorABI.nt("kk_op_fle", "lhs rhs"),
        operatorABI.nt("kk_op_flt", "lhs rhs"),
        operatorABI.nt("kk_op_fmod", "lhs rhs"),
        operatorABI.nt("kk_op_fmul", "lhs rhs"),
        operatorABI.nt("kk_op_fne", "lhs rhs"),
        operatorABI.nt("kk_op_fsub", "lhs rhs"),
        operatorABI.nt("kk_structural_ne", "lhs rhs"),
        operatorABI.th("kk_op_dfloor_mod", "lhs rhs"),
        operatorABI.th("kk_op_ffloor_mod", "lhs rhs"),
        operatorABI.th("kk_op_notnull", "value outThrown"),
        operatorABI.th("kk_op_notnull_msg", "value messageRaw outThrown"),
        operatorABI.nt("kk_nullable_primitive_eq", "nullableRaw peerRaw peerIsNullable"),
        operatorABI.nt("kk_nullable_primitive_ne", "nullableRaw peerRaw peerIsNullable"),
        operatorABI.nt("kk_nullable_double_equals", "lhs rhs"),
        operatorABI.nt("kk_nullable_float_equals", "lhs rhs"),
    ]

    static let collectionBridgeFunctions: [RuntimeABIFunctionSpec] =
        collectionBridgeBase
        + listClosureBridgeFunctions
        + listComparatorBridgeFunctions
        + mapBridgeFunctions
        + sequenceAndSetBridgeFunctions

    static let timeAndPathBridgeFunctions: [RuntimeABIFunctionSpec] = [
        systemABI.nt("kk_instant_compare", "aRaw bRaw"),
        systemABI.nt("kk_instant_epoch_seconds", "instantRaw"),
        systemABI.nt("kk_instant_from_epoch_millis", "millis"),
        systemABI.nt("kk_instant_is_distant_future", "instantRaw"),
        systemABI.nt("kk_instant_is_distant_past", "instantRaw"),
        systemABI.nt("kk_instant_minus_duration", "instantRaw durationRaw"),
        systemABI.nt("kk_instant_nano_of_second", "instantRaw"),
        systemABI.nt("kk_instant_now"),
        systemABI.nt("kk_instant_plus_duration", "instantRaw durationRaw"),
        systemABI.nt("kk_instant_until", "fromRaw toRaw"),
        systemABI.nt("kk_time_source_as_clock", "sourceRaw originRaw"),
        systemABI.th("kk_instant_from_epoch_seconds", "epochSeconds nanoOfSecond"),
        systemABI.nt("kk_platform_memoryModel", "platformRaw"),
        nativeABI.nt("kk_native_identityHashCode", "objectRaw"),
        nativeABI.nt("__kk_immutable_blob_of", "elements count"),
        nativeABI.nt("kk_native_getStackTraceAddresses", "throwableRaw"),
        nativeABI.nt("kk_native_getUnhandledExceptionHook"),
        nativeABI.nt("kk_native_setUnhandledExceptionHook", "hookRaw"),
        nativeABI.th("kk_native_processUnhandledException", "throwableRaw outThrown"),
        nativeABI.nt("kk_native_terminateWithUnhandledException", "throwableRaw", ret: .noreturn),
        nativeABI.nt("kk_native_byteArray_getByteAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getShortAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getIntAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getLongAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_setByteAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setShortAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setIntAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setLongAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_getUByteAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getUShortAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getUIntAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getULongAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_setUByteAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setUShortAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setUIntAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setULongAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_getCharAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getFloatAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_getDoubleAt", "arrayRaw index"),
        nativeABI.nt("kk_native_byteArray_setCharAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setFloatAt", "arrayRaw index value"),
        nativeABI.nt("kk_native_byteArray_setDoubleAt", "arrayRaw index value"),
        nativeABI.nt("__kk_immutable_blob_as_cpointer", "blobRaw offset"),
        systemABI.nt("kk_platform_isDebugBinary", "platformRaw"),
        // withTimeout reports an expired deadline as a catchable
        // TimeoutCancellationException, so its outThrown channel is declared
        // explicitly (as for kk_ensure_active) rather than left implicit.
        coroutineABI.th("kk_with_timeout", "timeoutMillis entryPointRaw continuation outThrown"),
        coroutineABI.nt("kk_with_timeout_or_null", "timeoutMillis entryPointRaw continuation"),
        coroutineABI.th("kk_with_timeout_or_null_throwing", "timeoutMillis entryPointRaw continuation outThrown"),
    ]

    static let dispatchBridgeFunctions: [RuntimeABIFunctionSpec] = [
        delegateABI.th("kk_itable_lookup", "receiver ifaceSlot methodSlot"),
        delegateABI.th("kk_itable_lookup_dynamic", "receiver interfaceTypeID methodSlot"),
        delegateABI.th("kk_vtable_lookup", "receiver slot"),
        // KUU-3910: guarded vtable lookup for `CoroutineDispatcher.isDispatchNeeded`
        // — native dispatcher objects have no Kotlin vtable, so they resolve the
        // source default while Kotlin dispatchers keep their vtable entry.
        delegateABI.th("kk_vtable_lookup_or_default", "receiver slot defaultMethod"),
    ]
}
