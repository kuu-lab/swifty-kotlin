import Foundation

private enum RuntimeDebugProbeState: Int, Sendable {
    case created = 0
    case running = 1
    case suspended = 2
    case cancelled = 3
}

private final class RuntimeDebugProbeEntry: @unchecked Sendable {
    weak var continuationState: RuntimeContinuationState?
    weak var job: RuntimeJobHandle?
    let creationStackTraceAddresses: [Int]
    var state: RuntimeDebugProbeState = .created

    init(
        continuationState: RuntimeContinuationState,
        job: RuntimeJobHandle,
        creationStackTraceAddresses: [Int]
    ) {
        self.continuationState = continuationState
        self.job = job
        self.creationStackTraceAddresses = creationStackTraceAddresses
    }
}

private struct RuntimeDebugProbeSnapshotEntry {
    let continuationState: RuntimeContinuationState
    let job: RuntimeJobHandle
    let state: RuntimeDebugProbeState
    let creationStackTrace: [String]
}

private final class RuntimeDebugProbeSnapshot: @unchecked Sendable {
    let entries: [RuntimeDebugProbeSnapshotEntry]

    init(entries: [RuntimeDebugProbeSnapshotEntry]) {
        self.entries = entries
    }
}

final class RuntimeCoroutineDebugProbes: @unchecked Sendable {
    static let shared = RuntimeCoroutineDebugProbes()

    private let lock = NSLock()
    private var installed = false
    private var creationStackTracesEnabled = false
    private var sanitizeStackTracesEnabled = true
    private var entries: [Int: RuntimeDebugProbeEntry] = [:]

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return installed
    }

    var enableCreationStackTraces: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return creationStackTracesEnabled
        }
        set {
            lock.lock()
            creationStackTracesEnabled = newValue
            lock.unlock()
        }
    }

    var sanitizeStackTraces: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return sanitizeStackTracesEnabled
        }
        set {
            lock.lock()
            sanitizeStackTracesEnabled = newValue
            lock.unlock()
        }
    }

    func install() {
        lock.lock()
        installed = true
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func uninstall() {
        lock.lock()
        installed = false
        entries.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func register(continuationState: RuntimeContinuationState, job: RuntimeJobHandle) {
        let continuation = Int(bitPattern: Unmanaged.passUnretained(continuationState).toOpaque())
        lock.lock()
        guard installed else {
            lock.unlock()
            return
        }
        if let existing = entries[continuation] {
            existing.continuationState = continuationState
            existing.job = job
            lock.unlock()
            return
        }
        let captureCreationStackTrace = creationStackTracesEnabled
        lock.unlock()

        let addresses = captureCreationStackTrace ? runtimeCurrentStackTraceAddresses() : []

        lock.lock()
        guard installed else {
            lock.unlock()
            return
        }
        if entries[continuation] == nil {
            entries[continuation] = RuntimeDebugProbeEntry(
                continuationState: continuationState,
                job: job,
                creationStackTraceAddresses: addresses
            )
        }
        lock.unlock()

        _ = job.addCompletionHandler(onCancelling: false) { [weak self] _ in
            self?.remove(continuation: continuation)
        }
    }

    func markRunning(continuation: Int) {
        updateState(.running, continuation: continuation)
    }

    func markSuspended(continuation: Int) {
        updateState(.suspended, continuation: continuation)
    }

    func remove(continuation: Int) {
        lock.lock()
        entries.removeValue(forKey: continuation)
        lock.unlock()
    }

    func makeSnapshotHandle() -> Int {
        lock.lock()
        guard installed else {
            lock.unlock()
            return 0
        }
        let shouldSanitize = sanitizeStackTracesEnabled
        let snapshotEntries = entries.values.compactMap { entry -> RuntimeDebugProbeSnapshotEntry? in
            guard let state = entry.continuationState,
                  !state.isExited,
                  let job = entry.job,
                  !job.completedSnapshot()
            else {
                return nil
            }
            let frames = runtimeThrowableStackFrameLines(entry.creationStackTraceAddresses)
            return RuntimeDebugProbeSnapshotEntry(
                continuationState: state,
                job: job,
                state: job.cancellationSnapshot() ? .cancelled : entry.state,
                creationStackTrace: shouldSanitize ? runtimeSanitizeCoroutineCreationStackTrace(frames) : frames
            )
        }
        lock.unlock()
        return runtimeRegisterObject(RuntimeDebugProbeSnapshot(entries: snapshotEntries))
    }

    private func updateState(_ state: RuntimeDebugProbeState, continuation: Int) {
        lock.lock()
        entries[continuation]?.state = state
        lock.unlock()
    }
}

private func runtimeSanitizeCoroutineCreationStackTrace(_ frames: [String]) -> [String] {
    let runtimeFrameMarkers = [
        "kk_debug_probes_",
        "kk_kxmini_launch",
        "runtimecoroutinedebugprobes",
        "runtimecurrentstacktraceaddresses",
        "runtimestartlaunchedbody",
        "runsuspendentryloopwithcontinuation",
    ]
    return frames.filter { frame in
        let lowercaseFrame = frame.lowercased()
        return !runtimeFrameMarkers.contains { marker in lowercaseFrame.contains(marker) }
    }
}

private func runtimeDebugProbeSnapshot(from handle: Int) -> RuntimeDebugProbeSnapshot? {
    guard handle != 0,
          let pointer = UnsafeMutableRawPointer(bitPattern: handle),
          runtimeStorage.withGCLock({ $0.objectPointers.contains(UInt(bitPattern: pointer)) })
    else {
        return nil
    }
    return tryCast(pointer, to: RuntimeDebugProbeSnapshot.self)
}

@_cdecl("kk_debug_probes_install")
public func kk_debug_probes_install() -> Int {
    RuntimeCoroutineDebugProbes.shared.install()
    return 0
}

@_cdecl("kk_debug_probes_uninstall")
public func kk_debug_probes_uninstall() -> Int {
    RuntimeCoroutineDebugProbes.shared.uninstall()
    return 0
}

@_cdecl("kk_debug_probes_is_installed")
public func kk_debug_probes_is_installed() -> Int {
    RuntimeCoroutineDebugProbes.shared.isInstalled ? 1 : 0
}

@_cdecl("kk_debug_probes_get_creation_stack_traces")
public func kk_debug_probes_get_creation_stack_traces() -> Int {
    RuntimeCoroutineDebugProbes.shared.enableCreationStackTraces ? 1 : 0
}

@_cdecl("kk_debug_probes_set_creation_stack_traces")
public func kk_debug_probes_set_creation_stack_traces(_ enabled: Int) -> Int {
    RuntimeCoroutineDebugProbes.shared.enableCreationStackTraces = enabled != 0
    return 0
}

@_cdecl("kk_debug_probes_get_sanitize_stack_traces")
public func kk_debug_probes_get_sanitize_stack_traces() -> Int {
    RuntimeCoroutineDebugProbes.shared.sanitizeStackTraces ? 1 : 0
}

@_cdecl("kk_debug_probes_set_sanitize_stack_traces")
public func kk_debug_probes_set_sanitize_stack_traces(_ enabled: Int) -> Int {
    RuntimeCoroutineDebugProbes.shared.sanitizeStackTraces = enabled != 0
    return 0
}

@_cdecl("kk_debug_probes_snapshot_create")
public func kk_debug_probes_snapshot_create() -> Int {
    RuntimeCoroutineDebugProbes.shared.makeSnapshotHandle()
}

@_cdecl("kk_debug_probes_snapshot_count")
public func kk_debug_probes_snapshot_count(_ snapshotHandle: Int) -> Int {
    runtimeDebugProbeSnapshot(from: snapshotHandle)?.entries.count ?? 0
}

@_cdecl("kk_debug_probes_snapshot_state")
public func kk_debug_probes_snapshot_state(_ snapshotHandle: Int, _ index: Int) -> Int {
    guard let snapshot = runtimeDebugProbeSnapshot(from: snapshotHandle),
          snapshot.entries.indices.contains(index)
    else {
        return -1
    }
    return snapshot.entries[index].state.rawValue
}

@_cdecl("kk_debug_probes_snapshot_context")
public func kk_debug_probes_snapshot_context(_ snapshotHandle: Int, _ index: Int) -> Int {
    guard let snapshot = runtimeDebugProbeSnapshot(from: snapshotHandle),
          snapshot.entries.indices.contains(index)
    else {
        return 0
    }
    let state = snapshot.entries[index].continuationState
    let context = state.makeContinuationContext()
    return state.generatedCoroutineContextIfMatching(context) ?? runtimeRegisterObject(context)
}

@_cdecl("kk_debug_probes_snapshot_creation_trace_count")
public func kk_debug_probes_snapshot_creation_trace_count(_ snapshotHandle: Int, _ index: Int) -> Int {
    guard let snapshot = runtimeDebugProbeSnapshot(from: snapshotHandle),
          snapshot.entries.indices.contains(index)
    else {
        return 0
    }
    return snapshot.entries[index].creationStackTrace.count
}

@_cdecl("kk_debug_probes_snapshot_creation_trace_at")
public func kk_debug_probes_snapshot_creation_trace_at(
    _ snapshotHandle: Int,
    _ index: Int,
    _ frameIndex: Int
) -> Int {
    guard let snapshot = runtimeDebugProbeSnapshot(from: snapshotHandle),
          snapshot.entries.indices.contains(index),
          snapshot.entries[index].creationStackTrace.indices.contains(frameIndex)
    else {
        return 0
    }
    return runtimeMakeStringRaw(snapshot.entries[index].creationStackTrace[frameIndex])
}

@_cdecl("kk_debug_probes_snapshot_release")
public func kk_debug_probes_snapshot_release(_ snapshotHandle: Int) -> Int {
    runtimeReleaseObject(snapshotHandle) ? 1 : 0
}
