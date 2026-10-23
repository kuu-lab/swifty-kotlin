private let abi = RuntimeABISectionBuilder("Result")

public extension RuntimeABISpec {
    static let resultFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_runtime_result_success", "value"),
        abi.nt("kk_runtime_result_is_success", "resultRaw"),
        abi.nt("kk_runtime_result_is_failure", "resultRaw"),
        abi.nt("kk_runtime_result_value_or_null", "resultRaw"),
        abi.th("kk_runtime_result_get_or_throw", "resultRaw outThrown"),
        abi.nt("kk_runtime_result_exception_or_null", "resultRaw"),
        abi.th("kk_runtime_result_run_catching", "fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_get_or_else", "resultRaw fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_map", "resultRaw fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_fold", "resultRaw successFnPtr successClosureRaw failureFnPtr failureClosureRaw outThrown"),
        abi.th("kk_runtime_result_on_success", "resultRaw fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_on_failure", "resultRaw fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_recover", "resultRaw fnPtr closureRaw outThrown"),
        abi.th("kk_runtime_result_recover_catching", "resultRaw fnPtr closureRaw outThrown"),
    ]
}
