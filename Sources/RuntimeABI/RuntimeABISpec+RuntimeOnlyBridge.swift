private let arraySpecialBridgeFunctions: [RuntimeABIFunctionSpec] = [
    abi.th("kk_bits_to_double", "value", ret: .double),
    abi.th("kk_bits_to_float", "value", ret: .float),
    abi.th("kk_double_to_bits", "value:double"),
    abi.th("kk_float_to_bits", "value:float"),
]

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
    bridgeSpec("__kk_flow_stopped", section: "Coroutine"),
    bridgeSpec("kk_supervisor_scope_new", section: "Coroutine"),
]

private let abi = RuntimeABISectionBuilder("NumericConversion")

public extension RuntimeABISpec {
    static let runtimeOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
        arraySpecialBridgeFunctions
        + minMaxFloatDoubleBridgeFunctions
        + coroutineOnlyBridgeFunctions
}
