private let abi = RuntimeABISectionBuilder("System")

public extension RuntimeABISpec {
    static let dynamicIteratorSpec: RuntimeABIFunctionSpec = abi.th("kk_dynamic_iterator", "value")

    static let systemFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_system_in"),
        abi.nt("__kk_system_getProperty", "propertyName"),
        // Compiler-only startup bridge: argc is the C int32 ABI and argv is
        // a borrowed pointer to a null-terminated C-string pointer vector.
        abi.nt("__kk_process_args_from_argv", "argc:int32 argv:nullableConstRawPointer"),
        abi.nt("__kk_system_exitProcess", "status", ret: .noreturn),
        abi.nt("__kk_system_currentTimeMillis"),
        abi.nt("__kk_system_nanoTime"),
        abi.nt("__kk_system_getTimeMicros"),
        abi.nt("__kk_system_getTimeMillis"),
        abi.nt("__kk_system_getTimeNanos"),
        abi.nt("__kk_system_process_start_nanos"),
        abi.nt("kk_platform_canAccessUnaligned", "platformRaw"),
        abi.nt("kk_platform_isLittleEndian", "platformRaw"),
        abi.nt("kk_platform_osFamily", "platformRaw"),
        abi.nt("kk_platform_cpuArchitecture", "platformRaw"),
        abi.nt("kk_platform_getAvailableProcessors", "platformRaw"),
        abi.nt("kk_platform_programName", "platformRaw"),
        abi.nt("kk_platform_isMemoryLeakCheckerActive_load", "platformRaw"),
        abi.nt("kk_platform_isMemoryLeakCheckerActive_store", "platformRaw value"),
        abi.nt("kk_platform_getAvailableProcessorsEnv", "platformRaw"),
        abi.nt("__kk_system_gc", ret: .void),
        abi.th("__kk_system_arraycopy", "sourceRaw sourcePosition destinationRaw destinationPosition length outThrown"),
        abi.nt("__kk_runtime_getRuntime"),
        abi.nt("__kk_runtime_totalMemory"),
        abi.nt("__kk_runtime_freeMemory"),
        abi.nt("__kk_runtime_maxMemory"),
        abi.nt("__kk_runtime_availableProcessors"),
        abi.nt("__kk_process_current_pid"),
        abi.nt("__kk_process_start", "commandRaw"),
        abi.nt("__kk_process_wait_for", "handle"),
        abi.nt("__kk_process_exit_value", "handle"),
        abi.nt("__kk_process_is_alive", "handle"),
        abi.nt("__kk_process_pid", "handle"),
        abi.nt("__kk_process_destroy", "handle", ret: .void),
        abi.nt("kk_clock_now", "receiver"),
        abi.nt("kk_clock_system_now"),
        dynamicIteratorSpec,
    ]
}
