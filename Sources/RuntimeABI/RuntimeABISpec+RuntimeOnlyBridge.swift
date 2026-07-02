private let arrayHOFBridgeNames = [
    "kk_array_all",
    "kk_array_count",
    "kk_array_find",
    "kk_array_findLast",
    "kk_array_flatMap",
    "kk_array_mapNotNull",
    "kk_array_reduce",
    "kk_array_reduceIndexed",
    "kk_array_reduceOrNull",
]

private let arrayHOFBridgeFunctions = arrayHOFBridgeNames.map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("arrayRaw", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let arrayFoldBridgeFunctions = [
    "kk_array_fold",
    "kk_array_foldIndexed",
].map {
    bridgeSpec(
        $0,
        section: "Collection",
        typedParams: [
            ("arrayRaw", .intptr),
            ("initial", .intptr),
            ("fnPtr", .intptr),
            ("closureRaw", .intptr),
            ("outThrown", .nullableIntptrPointer),
        ]
    )
}

private let arraySpecialBridgeFunctions: [RuntimeABIFunctionSpec] = [
    RuntimeABIFunctionSpec(
        name: "kk_bits_to_double",
        parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
        returnType: .double,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_bits_to_float",
        parameters: [RuntimeABIParameter(name: "value", type: .intptr)],
        returnType: .float,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_double_to_bits",
        parameters: [RuntimeABIParameter(name: "value", type: .double)],
        returnType: .intptr,
        section: "NumericConversion"
    ),
    RuntimeABIFunctionSpec(
        name: "kk_float_to_bits",
        parameters: [RuntimeABIParameter(name: "value", type: .float)],
        returnType: .intptr,
        section: "NumericConversion"
    ),
]

private let numericOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
    ["kk_byte_to_char", "kk_byte_to_uint", "kk_byte_to_ulong",
     "kk_short_to_char", "kk_short_to_uint", "kk_short_to_ulong"].map {
        bridgeSpec($0, section: "NumericConversion", params: ["value"])
    }

private let minMaxFloatDoubleBridgeFunctions: [RuntimeABIFunctionSpec] =
    ["kk_min_float", "kk_max_float", "kk_min_double", "kk_max_double"].map {
        bridgeSpec(
            $0,
            section: "NumericConversion",
            typedParams: [
                ("aBits", .intptr),
                ("bBits", .intptr),
            ],
            returnType: .intptr,
            isThrowing: false
        )
    }

private let coroutineOnlyBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec("kk_flow_stopped", section: "Coroutine"),
    bridgeSpec("kk_supervisor_scope_new", section: "Coroutine"),
]

private let kclassBridgeFunctions = [
    "kk_kclass_get_arity",
].map { bridgeSpec($0, section: "TypeCheck", params: ["kclassRaw"]) }

private let jsInteropBridgeFunctions: [RuntimeABIFunctionSpec] = [
    bridgeSpec(
        "kk_js_readonly_set_toMutableSet",
        section: "JsInterop",
        params: ["setRaw"]
    ),
]

private let sequenceOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
    [
        bridgeSpec(
            "kk_sequence_fold",
            section: "Sequence",
            typedParams: [
                ("seqRaw", .intptr),
                ("initial", .intptr),
                ("fnPtr", .intptr),
                ("closureRaw", .intptr),
                ("outThrown", .nullableIntptrPointer),
            ]
        ),
    ]

public extension RuntimeABISpec {
    static let runtimeOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
        arrayHOFBridgeFunctions
        + arrayFoldBridgeFunctions
        + arraySpecialBridgeFunctions
        + numericOnlyBridgeFunctions
        + minMaxFloatDoubleBridgeFunctions
        + coroutineOnlyBridgeFunctions
        + jsInteropBridgeFunctions
        + kclassBridgeFunctions
        + sequenceOnlyBridgeFunctions
}
