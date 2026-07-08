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
            name: "kk_runtime_result_is_failure",
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
            name: "kk_runtime_result_get_or_throw",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
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
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_run_catching",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_get_or_else",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_map",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_fold",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "successFnPtr", type: .intptr),
                RuntimeABIParameter(name: "successClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "failureFnPtr", type: .intptr),
                RuntimeABIParameter(name: "failureClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_on_success",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_on_failure",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_recover",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_result_recover_catching",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result",
            isThrowing: true
        ),
    ]
}
