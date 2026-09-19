public extension RuntimeABISpec {
    static let deepRecursiveFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_deep_recursive_function_new",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "launcherArgCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_deep_recursive_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "DeepRecursive",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_deep_recursive_scope_callRecursive",
            parameters: [
                RuntimeABIParameter(name: "scopeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_deep_recursive_function_callRecursive",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive",
            isThrowing: false
        ),
    ]
}
