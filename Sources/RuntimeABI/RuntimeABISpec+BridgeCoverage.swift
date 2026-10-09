func bridgeSpec(
    _ name: String,
    section: String,
    params: [String] = [],
    returnType: RuntimeABICType = .intptr,
    isThrowing: Bool = true
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: params.map { RuntimeABIParameter(name: $0, type: .intptr) },
        returnType: returnType,
        section: section,
        isThrowing: isThrowing
    )
}

func bridgeSpec(
    _ name: String,
    section: String,
    typedParams: [(String, RuntimeABICType)],
    returnType: RuntimeABICType = .intptr,
    isThrowing: Bool = true
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: typedParams.map { RuntimeABIParameter(name: $0.0, type: $0.1) },
        returnType: returnType,
        section: section,
        isThrowing: isThrowing
    )
}

private let collectionBridgeBase: [RuntimeABIFunctionSpec] = [
    bridgeSpec(
        "kk_iterable_iterator",
        section: "Collection",
        typedParams: [
            ("iterableRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    ),
]

private func listClosureBridgeSpec(_ name: String) -> RuntimeABIFunctionSpec {
    bridgeSpec(
        name,
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let listClosureBridgeFunctions = [
    RuntimeABISpec.listMaxOfSpec,
    RuntimeABISpec.listMaxWithSpec,
    RuntimeABISpec.listMaxWithOrNullSpec,
    RuntimeABISpec.listMinOfSpec,
    RuntimeABISpec.listMinWithSpec,
    RuntimeABISpec.listMinWithOrNullSpec,
]

private func listComparatorBridgeSpec(_ name: String) -> RuntimeABIFunctionSpec {
    bridgeSpec(
        name,
        section: "Collection",
        typedParams: [
            ("listRaw", .intptr),
            ("cmpFnPtr", .intptr),
            ("cmpClosureRaw", .intptr),
            ("selFnPtr", .intptr),
            ("selClosureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let listComparatorBridgeFunctions = [
    RuntimeABISpec.listMaxOfWithSpec,
    RuntimeABISpec.listMaxOfWithOrNullSpec,
    RuntimeABISpec.listMinOfWithSpec,
    RuntimeABISpec.listMinOfWithOrNullSpec,
]

private let listIndexedBridgeFunctions: [RuntimeABIFunctionSpec] = []

private let listMiscBridgeFunctions: [RuntimeABIFunctionSpec] = []

private func mapBridgeSpec(_ name: String) -> RuntimeABIFunctionSpec {
    bridgeSpec(
        name,
        section: "Collection",
        typedParams: [
            ("mapRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let mapBridgeFunctions = [
    RuntimeABISpec.mapFlatMapSpec,
    RuntimeABISpec.mapMaxByOrNullSpec,
    RuntimeABISpec.mapMinByOrNullSpec,
]

private let sequenceAndSetBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_range_hasNext", section: "Range", params: ["iterRaw"],
            isThrowing: false),
    bridgeSpec("kk_range_iterator", section: "Range", typedParams: [
        ("rangeRaw", .intptr),
        ("outThrown", .nullableIntptrPointer),
    ]),
    bridgeSpec("kk_range_next", section: "Range", params: ["iterRaw"],
            isThrowing: false),
    bridgeSpec("kk_range_for_in_hasNext", section: "Range", params: ["iterRaw"],
            isThrowing: false),
    bridgeSpec("kk_range_for_in_iterator", section: "Range", params: ["rangeRaw"],
            isThrowing: false),
    bridgeSpec("kk_range_for_in_next", section: "Range", params: ["iterRaw"],
            isThrowing: false),
    RuntimeABISpec.sequenceFilterNotSpec,
    bridgeSpec("__kk_set_of_not_null", section: "Collection", params: ["arrayRaw", "count"],
            isThrowing: false),
]

public extension RuntimeABISpec {
    static let listMaxOfSpec = listClosureBridgeSpec("kk_list_maxOf")
    static let listMaxWithSpec = listClosureBridgeSpec("kk_list_maxWith")
    static let listMaxWithOrNullSpec = listClosureBridgeSpec("kk_list_maxWithOrNull")
    static let listMinOfSpec = listClosureBridgeSpec("kk_list_minOf")
    static let listMinWithSpec = listClosureBridgeSpec("kk_list_minWith")
    static let listMinWithOrNullSpec = listClosureBridgeSpec("kk_list_minWithOrNull")
    static let listMaxOfWithSpec = listComparatorBridgeSpec("kk_list_maxOfWith")
    static let listMaxOfWithOrNullSpec = listComparatorBridgeSpec("kk_list_maxOfWithOrNull")
    static let listMinOfWithSpec = listComparatorBridgeSpec("kk_list_minOfWith")
    static let listMinOfWithOrNullSpec = listComparatorBridgeSpec("kk_list_minOfWithOrNull")
    static let mapFlatMapSpec = mapBridgeSpec("kk_map_flatMap")
    static let mapMaxByOrNullSpec = mapBridgeSpec("kk_map_maxByOrNull")
    static let mapMinByOrNullSpec = mapBridgeSpec("kk_map_minByOrNull")

    static let sequenceFilterNotSpec: RuntimeABIFunctionSpec = bridgeSpec("kk_sequence_filterNot", section: "Sequence", params: ["seqRaw", "fnPtr", "closureRaw"],
            isThrowing: false)

    static let numericRuntimeBridgeFunctions: [RuntimeABIFunctionSpec] =
        [
            "kk_char_category",
            "kk_char_code",
            "kk_char_directionality",
            "kk_char_toDouble",
            "kk_char_toDoubleOrNull",
            "kk_char_toInt",
            "kk_char_toIntOrNull",
        ].map { bridgeSpec($0, section: "Char", params: ["value"]) }
        + [
            bridgeSpec("__kk_double_toBits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_double_toRawBits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_double_fromBits", section: "NumericConversion", params: ["bits"],
            isThrowing: false),
            bridgeSpec("__kk_double_to_int", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_double_to_long", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_float_fromBits", section: "NumericConversion", params: ["bits"],
            isThrowing: false),
            bridgeSpec("__kk_float_toBits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_float_toRawBits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_float_to_double_bits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_float_to_int", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("__kk_float_to_long", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_int_to_double_bits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_int_to_float_bits", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_int_to_long", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_int_to_uint", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_int_to_ulong", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_long_to_uint", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_long_to_ulong", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_uint_to_int", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_uint_to_long", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_uint_to_ulong", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_ulong_to_int", section: "NumericConversion", params: ["value"],
            isThrowing: false),
            bridgeSpec("kk_ulong_to_long", section: "NumericConversion", params: ["value"],
            isThrowing: false),
        ]
        + [
            "kk_op_dadd",
            "kk_op_ddiv",
            "kk_op_deq",
            "kk_op_dge",
            "kk_op_dgt",
            "kk_op_dle",
            "kk_op_dlt",
            "kk_op_dmod",
            "kk_op_dne",
            "kk_op_dsub",
            "kk_op_elvis",
            "kk_op_fadd",
            "kk_op_fdiv",
            "kk_op_feq",
            "kk_op_fge",
            "kk_op_fgt",
            "kk_op_fle",
            "kk_op_flt",
            "kk_op_fmod",
            "kk_op_fmul",
            "kk_op_fne",
            "kk_op_fsub",
            "kk_structural_ne",
        ].map { bridgeSpec($0, section: "Operator", params: ["lhs", "rhs"], isThrowing: false) }
        + [
            "kk_op_dfloor_mod",
            "kk_op_ffloor_mod",
        ].map { bridgeSpec($0, section: "Operator", params: ["lhs", "rhs"]) }
        + [
            bridgeSpec(
                "kk_op_notnull",
                section: "Operator",
                typedParams: [
                    ("value", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            ),
        ]
        + [
            "kk_nullable_primitive_eq",
            "kk_nullable_primitive_ne",
        ].map {
            bridgeSpec($0, section: "Operator", params: ["nullableRaw", "peerRaw", "peerIsNullable"], isThrowing: false)
        }

    static let collectionBridgeFunctions: [RuntimeABIFunctionSpec] =
        collectionBridgeBase
        + listClosureBridgeFunctions
        + listComparatorBridgeFunctions
        + listIndexedBridgeFunctions
        + listMiscBridgeFunctions
        + mapBridgeFunctions
        + sequenceAndSetBridgeFunctions

    static let timeAndPathBridgeFunctions: [RuntimeABIFunctionSpec] =
        [
            bridgeSpec("kk_instant_compare", section: "System", params: ["aRaw", "bRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_epoch_seconds", section: "System", params: ["instantRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_from_epoch_millis", section: "System", params: ["millis"],
            isThrowing: false),
            bridgeSpec("kk_instant_is_distant_future", section: "System", params: ["instantRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_is_distant_past", section: "System", params: ["instantRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_minus_duration", section: "System", params: ["instantRaw", "durationRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_nano_of_second", section: "System", params: ["instantRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_now", section: "System",
            isThrowing: false),
            bridgeSpec("kk_instant_plus_duration", section: "System", params: ["instantRaw", "durationRaw"],
            isThrowing: false),
            bridgeSpec("kk_instant_until", section: "System", params: ["fromRaw", "toRaw"],
            isThrowing: false),
            bridgeSpec("kk_time_source_as_clock", section: "System", params: ["sourceRaw", "originRaw"],
            isThrowing: false),
            // STDLIB-TIME-181: Native Foundation Date bridge
            // STDLIB-TIME-181: Native clock_gettime bridge
            // STDLIB-TIME-181: Type-safe epoch conversion helpers
            bridgeSpec("kk_instant_from_epoch_seconds", section: "System", params: ["epochSeconds", "nanoOfSecond"]),
            bridgeSpec("kk_platform_memoryModel", section: "System", params: ["platformRaw"],
            isThrowing: false),
            bridgeSpec("kk_native_identityHashCode", section: "Native", params: ["objectRaw"],
            isThrowing: false),
            bridgeSpec("__kk_immutable_blob_of", section: "Native", params: ["elements", "count"],
            isThrowing: false),
            bridgeSpec("kk_native_getStackTraceAddresses", section: "Native", params: ["throwableRaw"],
            isThrowing: false),
            bridgeSpec("kk_native_getUnhandledExceptionHook", section: "Native", params: [],
            isThrowing: false),
            bridgeSpec("kk_native_setUnhandledExceptionHook", section: "Native", params: ["hookRaw"],
            isThrowing: false),
            bridgeSpec(
                "kk_native_processUnhandledException",
                section: "Native",
                typedParams: [
                    ("throwableRaw", .intptr),
                    ("outThrown", .nullableIntptrPointer),
                ]
            ),
            bridgeSpec("kk_native_terminateWithUnhandledException", section: "Native", params: ["throwableRaw"],
            returnType: .noreturn,
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getByteAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getShortAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getIntAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getLongAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setByteAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setShortAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setIntAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setLongAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getUByteAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getUShortAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getUIntAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getULongAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setUByteAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setUShortAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setUIntAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setULongAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getCharAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getFloatAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_getDoubleAt", section: "Native", params: ["arrayRaw", "index"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setCharAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setFloatAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            bridgeSpec("kk_native_byteArray_setDoubleAt", section: "Native", params: ["arrayRaw", "index", "value"],
            isThrowing: false),
            // KSP-1192: ImmutableBlob.asCPointer/asUCPointer private impl bridge.
            bridgeSpec("__kk_immutable_blob_as_cpointer", section: "Native", params: ["blobRaw", "offset"],
            isThrowing: false),
            bridgeSpec("kk_platform_isDebugBinary", section: "System", params: ["platformRaw"],
            isThrowing: false),
            // withTimeout reports an expired deadline as a catchable
            // TimeoutCancellationException, so its outThrown channel is declared
            // explicitly (as for kk_ensure_active) rather than left implicit.
            bridgeSpec("kk_with_timeout", section: "Coroutine", typedParams: [
                ("timeoutMillis", .intptr),
                ("entryPointRaw", .intptr),
                ("continuation", .intptr),
                ("outThrown", .nullableIntptrPointer),
            ]),
            bridgeSpec("kk_with_timeout_or_null", section: "Coroutine", params: ["timeoutMillis", "entryPointRaw", "continuation"],
            isThrowing: false),
            bridgeSpec("kk_with_timeout_or_null_throwing", section: "Coroutine", typedParams: [
                ("timeoutMillis", .intptr),
                ("entryPointRaw", .intptr),
                ("continuation", .intptr),
                ("outThrown", .nullableIntptrPointer),
            ]),
        ]

    static let dispatchBridgeFunctions: [RuntimeABIFunctionSpec] = [
        bridgeSpec("kk_itable_lookup", section: "Delegate", params: ["receiver", "ifaceSlot", "methodSlot"]),
        bridgeSpec("kk_itable_lookup_dynamic", section: "Delegate", params: ["receiver", "interfaceTypeID", "methodSlot"]),
        bridgeSpec("kk_vtable_lookup", section: "Delegate", params: ["receiver", "slot"]),
    ]

    static let stringBridgeFunctions: [RuntimeABIFunctionSpec] = [
    ]
}
