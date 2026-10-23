private let abi = RuntimeABISectionBuilder("DeepRecursive")

public extension RuntimeABISpec {
    static let deepRecursiveFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_deep_recursive_function_new", "fnPtr functionID closureRaw launcherArgCount"),
        abi.th("__kk_deep_recursive_function_invoke", "functionRaw value outThrown"),
        abi.nt("__kk_deep_recursive_scope_callRecursive", "scopeRaw value continuation"),
        abi.nt("__kk_deep_recursive_function_callRecursive", "functionRaw value continuation"),
    ]
}
