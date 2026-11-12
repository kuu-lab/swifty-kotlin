private let abi = RuntimeABISectionBuilder("NumericConversion")
private let coroutineABI = RuntimeABISectionBuilder("Coroutine")

private let arraySpecialBridgeFunctions: [RuntimeABIFunctionSpec] = [
    abi.th("kk_bits_to_double", "value", ret: .double),
    abi.th("kk_bits_to_float", "value", ret: .float),
    abi.th("kk_double_to_bits", "value:double"),
    abi.th("kk_float_to_bits", "value:float"),
]

private let minMaxFloatDoubleBridgeFunctions: [RuntimeABIFunctionSpec] = [
    abi.nt("kk_min_float", "aBits bBits"),
    abi.nt("kk_max_float", "aBits bBits"),
    abi.nt("kk_min_double", "aBits bBits"),
    abi.nt("kk_max_double", "aBits bBits"),
]

private let coroutineOnlyBridgeFunctions: [RuntimeABIFunctionSpec] = [
    coroutineABI.th("__kk_flow_stopped"),
    coroutineABI.th("kk_supervisor_scope_new"),
]

public extension RuntimeABISpec {
    static let runtimeOnlyBridgeFunctions: [RuntimeABIFunctionSpec] =
        arraySpecialBridgeFunctions
        + minMaxFloatDoubleBridgeFunctions
        + coroutineOnlyBridgeFunctions
}
