private let coroutineProbesABI = RuntimeABISectionBuilder("Coroutine")

public extension RuntimeABISpec {
    static let coroutineDebugProbesFunctions: [RuntimeABIFunctionSpec] = [
        coroutineProbesABI.nt("kk_debug_probes_get_creation_stack_traces"),
        coroutineProbesABI.nt("kk_debug_probes_get_sanitize_stack_traces"),
        coroutineProbesABI.nt("kk_debug_probes_install"),
        coroutineProbesABI.nt("kk_debug_probes_is_installed"),
        coroutineProbesABI.nt("kk_debug_probes_set_creation_stack_traces", "enabled"),
        coroutineProbesABI.nt("kk_debug_probes_set_sanitize_stack_traces", "enabled"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_context", "snapshotHandle index"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_count", "snapshotHandle"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_create"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_creation_trace_at", "snapshotHandle index frameIndex"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_creation_trace_count", "snapshotHandle index"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_release", "snapshotHandle"),
        coroutineProbesABI.nt("kk_debug_probes_snapshot_state", "snapshotHandle index"),
        coroutineProbesABI.nt("kk_debug_probes_uninstall"),
    ]
}
