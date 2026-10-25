private let abi = RuntimeABISectionBuilder("Delegate")
private let abiCoroutine = RuntimeABISectionBuilder("Coroutine")

public extension RuntimeABISpec {
    static let suspendFunctionInvokeSpec: RuntimeABIFunctionSpec = abiCoroutine.th("kk_suspend_function_invoke", "functionRaw arg continuation outThrown")
    static let suspendFunctionInvoke0Spec: RuntimeABIFunctionSpec = abiCoroutine.th("kk_suspend_function_invoke_0", "functionRaw continuation outThrown")
    static let suspendFunctionInvoke2Spec: RuntimeABIFunctionSpec = abiCoroutine.th("kk_suspend_function_invoke_2", "functionRaw arg1 arg2 continuation outThrown")
    static let suspendFunctionCreateSpec: RuntimeABIFunctionSpec = abiCoroutine.nt("kk_suspend_function_create", "bodyRaw closureRaw arity entryPointRaw")
    static let suspendFunctionInvoke3Spec: RuntimeABIFunctionSpec = abiCoroutine.th("kk_suspend_function_invoke_3", "functionRaw arg1 arg2 arg3 continuation outThrown")

    static let delegateFunctions: [RuntimeABIFunctionSpec] = [
        // Lazy(SYNCHRONIZED) locking (KSP-491). `lazy`/`Delegates.observable/vetoable/notNull`
        // themselves are bundled Kotlin source (Stdlib/kotlin/Lazy.kt,
        // Stdlib/kotlin/properties/{ObservableProperty,Delegates}.kt); this pair is the
        // only runtime bridge they still need (reason code: GC/continuation-adjacent
        // per-object locking, same rationale as `__kk_synchronized`).
        abi.nt("__kk_lazy_sync_lock", "handle"),
        abi.nt("__kk_lazy_sync_unlock", "handle"),
        abi.nt("kk_function_value_tag_arity", "functionRaw arity"),
        abi.th("kk_function_invoke", "functionRaw arg outThrown"),
        abi.th("kk_function_invoke_0", "functionRaw outThrown"),
        suspendFunctionInvokeSpec,
        suspendFunctionInvoke0Spec,
        suspendFunctionInvoke2Spec,
        suspendFunctionCreateSpec,
        suspendFunctionInvoke3Spec,
        abiCoroutine.th("kk_suspend_function_invoke_4", "functionRaw arg1 arg2 arg3 arg4 continuation outThrown"),
        abiCoroutine.th("kk_suspend_function_invoke_5", "functionRaw arg1 arg2 arg3 arg4 arg5 continuation outThrown"),
        abiCoroutine.th("kk_suspend_function_invoke_6", "functionRaw arg1 arg2 arg3 arg4 arg5 arg6 continuation outThrown"),
        abi.th("kk_function_invoke_2", "functionRaw arg1 arg2 outThrown"),
        abi.th("kk_function_invoke_3", "functionRaw arg1 arg2 arg3 outThrown"),
        abi.th("kk_function_invoke_4", "functionRaw arg1 arg2 arg3 arg4 outThrown"),
        abi.th("kk_function_invoke_5", "functionRaw arg1 arg2 arg3 arg4 arg5 outThrown"),
        abi.th("kk_function_invoke_6", "functionRaw arg1 arg2 arg3 arg4 arg5 arg6 outThrown"),
    ] + (7...22).map { arity in
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_\(arity)",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ] + (1...arity).map { argument in
                RuntimeABIParameter(name: "arg\(argument)", type: .intptr)
            } + [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        )
    } + [
        abi.th("kk_function_create_0", "bodyRaw closureRaw outThrown"),
        abi.th("kk_function_create_1", "bodyRaw closureRaw outThrown"),
        abi.nt("kk_function_value_fn_ptr", "functionRaw"),
        abi.nt("kk_function_value_closure_raw", "functionRaw"),
        abi.th("kk_function_create_2", "bodyRaw closureRaw outThrown"),
        abi.th("kk_function_create_3", "bodyRaw closureRaw outThrown"),
        abi.th("kk_function_create_4", "bodyRaw closureRaw outThrown"),
        abi.th("kk_function_create_5", "bodyRaw closureRaw outThrown"),
        abi.th("kk_function_create_6", "bodyRaw closureRaw outThrown"),
    ]
}
