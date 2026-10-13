// ThreadLocal (java.lang.ThreadLocal / kotlin.concurrent.getOrSet)

public extension RuntimeABISpec {
    static let threadLocalNewSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_thread_local_new",
        parameters: [],
        returnType: .intptr,
        section: "ThreadLocal",
        isThrowing: false,
    )

    static let threadLocalGetOrSetSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_thread_local_getOrSet",
        parameters: [
            RuntimeABIParameter(name: "receiver", type: .intptr),
            RuntimeABIParameter(name: "fnPtr", type: .intptr),
            RuntimeABIParameter(name: "closureRaw", type: .intptr),
            RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
        ],
        returnType: .intptr,
        section: "ThreadLocal"
    )

    static let threadLocalFunctions: [RuntimeABIFunctionSpec] = [
        threadLocalNewSpec,
        threadLocalGetOrSetSpec,
    ]
}
