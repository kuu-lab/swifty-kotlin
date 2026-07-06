public extension RuntimeABISpec {
    static let resultFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_success",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_failure",
            parameters: [
                RuntimeABIParameter(name: "exception", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_is_success",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_value_or_null",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_exception_or_null",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: false
        ),
    ]
}
