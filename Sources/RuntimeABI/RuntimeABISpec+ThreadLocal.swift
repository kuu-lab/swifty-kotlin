// ThreadLocal (java.lang.ThreadLocal / kotlin.concurrent.getOrSet)

public extension RuntimeABISpec {
    static let threadLocalNewBridgeSpec = RuntimeABIFunctionSpec(
        name: "__kk_thread_local_new",
        parameters: [],
        returnType: .intptr,
        section: "ThreadLocal",
        isThrowing: false
    )

    static let threadLocalHasValueBridgeSpec = RuntimeABIFunctionSpec(
        name: "__kk_thread_local_has_value",
        parameters: [RuntimeABIParameter(name: "receiver", type: .intptr)],
        returnType: .intptr,
        section: "ThreadLocal",
        isThrowing: false
    )

    static let threadLocalValueBridgeSpec = RuntimeABIFunctionSpec(
        name: "__kk_thread_local_value",
        parameters: [RuntimeABIParameter(name: "receiver", type: .intptr)],
        returnType: .intptr,
        section: "ThreadLocal",
        isThrowing: false
    )

    static let threadLocalStoreBridgeSpec = RuntimeABIFunctionSpec(
        name: "__kk_thread_local_store",
        parameters: [RuntimeABIParameter(name: "receiver", type: .intptr), RuntimeABIParameter(name: "value", type: .intptr)],
        returnType: .intptr,
        section: "ThreadLocal",
        isThrowing: false
    )

    static let threadLocalFunctions: [RuntimeABIFunctionSpec] = [
        threadLocalNewBridgeSpec,
        threadLocalHasValueBridgeSpec,
        threadLocalValueBridgeSpec,
        threadLocalStoreBridgeSpec,
    ]
}
