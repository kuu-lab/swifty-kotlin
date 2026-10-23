public extension RuntimeABISpec {
    static let coroutineDebugProbesFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_get_creation_stack_traces",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_get_sanitize_stack_traces",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_install",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_is_installed",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_set_creation_stack_traces",
            parameters: [RuntimeABIParameter(name: "enabled", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_set_sanitize_stack_traces",
            parameters: [RuntimeABIParameter(name: "enabled", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_context",
            parameters: [
                RuntimeABIParameter(name: "snapshotHandle", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_count",
            parameters: [RuntimeABIParameter(name: "snapshotHandle", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_create",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_creation_trace_at",
            parameters: [
                RuntimeABIParameter(name: "snapshotHandle", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "frameIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_creation_trace_count",
            parameters: [
                RuntimeABIParameter(name: "snapshotHandle", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_release",
            parameters: [RuntimeABIParameter(name: "snapshotHandle", type: .intptr)],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_snapshot_state",
            parameters: [
                RuntimeABIParameter(name: "snapshotHandle", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_debug_probes_uninstall",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine",
            isThrowing: false
        ),
    ]
}
