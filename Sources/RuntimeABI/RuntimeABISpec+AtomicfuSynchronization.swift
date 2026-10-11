// Private real thread/lock/parking kernels. Public API is bundled Kotlin source.
public extension RuntimeABISpec {
    static let atomicfuSynchronizationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_lock_new",
            parameters: [
                RuntimeABIParameter(name: "ownerErrorKind", type: .intptr),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: false,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_lock_lock",
            parameters: [
                RuntimeABIParameter(name: "kernel", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_lock_try_lock",
            parameters: [
                RuntimeABIParameter(name: "kernel", type: .intptr),
                RuntimeABIParameter(name: "timeoutNanos", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_lock_unlock",
            parameters: [
                RuntimeABIParameter(name: "kernel", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_parker_new",
            parameters: [],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: false,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_parker_wait",
            parameters: [
                RuntimeABIParameter(name: "kernel", type: .intptr),
                RuntimeABIParameter(name: "timeoutNanos", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_parker_unpark",
            parameters: [
                RuntimeABIParameter(name: "kernel", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_atomicfu_current_parking_handle",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "AtomicfuSynchronization",
            isThrowing: true,
            returnsRawBoolean: false
        ),
    ]
}
