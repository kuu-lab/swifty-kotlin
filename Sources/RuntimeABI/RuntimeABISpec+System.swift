// swiftlint:disable file_length

/// `RuntimeABISpec.systemFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let systemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_system_exitProcess",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .noreturn,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_currentTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_nanoTime",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMicros",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeNanos",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_process_start_nanos",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMillis",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMicros",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureNanoTime",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_canAccessUnaligned",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_isLittleEndian",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_osFamily",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_cpuArchitecture",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_getAvailableProcessors",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_gc",
            parameters: [],
            returnType: .void,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_getRuntime",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_totalMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_freeMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_maxMemory",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "System",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_system_now",
            parameters: [],
            returnType: .intptr,
            section: "System",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_java_instant",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dynamic_iterator",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
    ]
}
