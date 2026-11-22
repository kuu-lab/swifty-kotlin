import Foundation

private let selectBuilderKey = "KSwiftK.selectBuilder"

/// Serializes every selection decision across all `select` instances.
///
/// Channel and mutex operations acquire this lock while holding their own
/// state lock; the established order is always channel/mutex lock → claim
/// lock, and select code never acquires a channel/mutex lock while holding
/// this one (the finish path releases it before touching channel queues).
/// While the lock is held a rendezvous can be committed by exactly one
/// clause: a second claimant observes a non-nil `selectedClause` and backs
/// off, so the same element is never delivered to two clauses.
let runtimeSelectClaimLock = NSLock()

let kSelectResultDecided = 4

/// Per-`select {}` state shared between the bundled `SelectImplementation`
/// and the runtime objects its clauses poll. Every mutable field is touched
/// only under `runtimeSelectClaimLock`.
final class RuntimeSelectState: @unchecked Sendable {
    private(set) var selectedClause: RuntimeSelectClause?
    private(set) var finished = false

    /// Marks the select finished. Caller must hold `runtimeSelectClaimLock`.
    func markFinishedUnlocked() {
        finished = true
    }
    var pendingWaiters: [(channel: RuntimeChannelHandle, waiter: RuntimeSelectWaiter)] = []

    /// Atomic single-shot claim. Caller must hold `runtimeSelectClaimLock`.
    /// Returns `true` when this call wins the selection for `clause`, or
    /// when `clause` already owns it; `false` when another clause won or
    /// the select is finished.
    func trySelectUnlocked(_ clause: RuntimeSelectClause) -> Bool {
        if finished { return false }
        if let selected = selectedClause { return selected === clause }
        selectedClause = clause
        return true
    }

    /// `true` once a clause owns the selection or the select finished.
    /// Caller must hold `runtimeSelectClaimLock`.
    var isDecidedUnlocked: Bool {
        selectedClause != nil || finished
    }
}

final class RuntimeSelectClause: @unchecked Sendable {
    weak var select: RuntimeSelectState?

    init(select: RuntimeSelectState) {
        self.select = select
    }

    var delivered = false
    var deliveredStatus = 0
    var deliveredValue = 0 {
        didSet { valueRoot = RuntimeGCRootedValue(deliveredValue) }
    }
    var deliveredCause = 0 {
        didSet { causeRoot = RuntimeGCRootedValue(deliveredCause) }
    }
    private var valueRoot: RuntimeGCRootedValue?
    private var causeRoot: RuntimeGCRootedValue?
    var waiterRegistered = false
}

final class RuntimeSelectWaiter: @unchecked Sendable {
    weak var clause: RuntimeSelectClause?
    private let valueRoot: RuntimeGCRootedValue
    var value: Int { valueRoot.value }

    func rootedValue() -> Int { valueRoot.rootedValue() }

    init(clause: RuntimeSelectClause, value: Int) {
        self.clause = clause
        self.valueRoot = RuntimeGCRootedValue(value)
    }
}

@_cdecl("__kk_select_start_job")
public func __kk_select_start_job(_ handle: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else { return 0 }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let job = object as? RuntimeJobHandle {
        job.startIfNeeded()
    } else if let task = object as? RuntimeAsyncTask {
        task.startIfNeeded()
    }
    return 0
}
@_cdecl("__kk_select_builder_exchange")
public func __kk_select_builder_exchange(_ builder: Int) -> Int {
    let previous = __kk_select_builder_current()
    if builder == runtimeNullSentinelInt {
        Thread.current.threadDictionary.removeObject(forKey: selectBuilderKey)
    } else {
        Thread.current.threadDictionary[selectBuilderKey] = builder
    }
    return previous
}

@_cdecl("__kk_select_builder_current")
public func __kk_select_builder_current() -> Int {
    Thread.current.threadDictionary[selectBuilderKey] as? Int ?? runtimeNullSentinelInt
}

@_cdecl("__kk_select_try_receive")
public func __kk_select_try_receive(_ handle: Int) -> Int {
    __kk_channel_try_receive(handle)
}

public func __kk_select_receive_value(_ token: Int) -> Int {
    __kk_channel_result_value_or_null(token)
}

@_cdecl("__kk_select_state_new")
public func __kk_select_state_new() -> Int {
    registerRuntimeObject(RuntimeSelectState())
}

@_cdecl("__kk_select_clause_new")
public func __kk_select_clause_new(_ stateRaw: Int) -> Int {
    guard let state = resolveRuntimeHandle(stateRaw, as: RuntimeSelectState.self) else {
        return 0
    }
    return registerRuntimeObject(RuntimeSelectClause(select: state))
}

@_cdecl("__kk_select_try_select")
public func __kk_select_try_select(_ clauseRaw: Int) -> Int {
    guard let clause = resolveRuntimeHandle(clauseRaw, as: RuntimeSelectClause.self),
          let state = clause.select else { return 0 }
    runtimeSelectClaimLock.lock()
    let won = state.trySelectUnlocked(clause)
    runtimeSelectClaimLock.unlock()
    return won ? 1 : 0
}

@_cdecl("__kk_select_try_select_result")
public func __kk_select_try_select_result(_ clauseRaw: Int, _ result: Int) -> Int {
    guard let clause = resolveRuntimeHandle(clauseRaw, as: RuntimeSelectClause.self),
          let state = clause.select else { return 0 }
    runtimeSelectClaimLock.lock()
    let won = state.trySelectUnlocked(clause)
    if won {
        clause.delivered = true
        clause.deliveredStatus = kChannelResultSuccess
        clause.deliveredValue = result
    }
    runtimeSelectClaimLock.unlock()
    return won ? 1 : 0
}

@_cdecl("__kk_select_mark_selected")
public func __kk_select_mark_selected(_ stateRaw: Int) -> Int {
    guard let state = resolveRuntimeHandle(stateRaw, as: RuntimeSelectState.self) else {
        return 0
    }
    runtimeSelectClaimLock.lock()
    state.markFinishedUnlocked()
    runtimeSelectClaimLock.unlock()
    return 0
}

@_cdecl("__kk_select_selected_clause")
public func __kk_select_selected_clause(_ stateRaw: Int) -> Int {
    guard let state = resolveRuntimeHandle(stateRaw, as: RuntimeSelectState.self) else {
        return runtimeNullSentinelInt
    }
    runtimeSelectClaimLock.lock()
    let clause = state.selectedClause
    runtimeSelectClaimLock.unlock()
    guard let clause else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: Unmanaged.passUnretained(clause).toOpaque())
}

/// consumable offer behind. The claim lock is released before taking any
/// channel lock — the lock order is always channel → claim.
@_cdecl("__kk_select_state_finish")
public func __kk_select_state_finish(_ stateRaw: Int) -> Int {
    guard let state = resolveRuntimeHandle(stateRaw, as: RuntimeSelectState.self) else {
        return 0
    }
    runtimeSelectClaimLock.lock()
    state.markFinishedUnlocked()
    let waiters = state.pendingWaiters
    state.pendingWaiters.removeAll()
    runtimeSelectClaimLock.unlock()
    for (channel, waiter) in waiters {
        channel.removeSelectWaiter(waiter)
    }
    return 0
}

@_cdecl("__kk_select_poll_receive")
public func __kk_select_poll_receive(_ handle: Int, _ clauseRaw: Int) -> Int {
    guard let channel = runtimeChannelHandleObject(from: handle),
          let clause = resolveRuntimeHandle(clauseRaw, as: RuntimeSelectClause.self) else {
        return runtimeSelectPollResultBox(status: kChannelResultFailed)
    }
    return channel.selectPollReceive(clause: clause)
}

/// `onSend` poll: mirrors `trySend` plus waiter registration. Returns the
/// same status layout the clause expects (0 sent, 1 closed, 2 cancelled,
/// 3 still pending) plus the internal "decided elsewhere" marker.
@_cdecl("__kk_select_poll_send")
public func __kk_select_poll_send(_ handle: Int, _ clauseRaw: Int, _ value: Int) -> Int {
    guard let channel = runtimeChannelHandleObject(from: handle),
          let clause = resolveRuntimeHandle(clauseRaw, as: RuntimeSelectClause.self) else {
        return kChannelResultFailed
    }
    return channel.selectPollSend(clause: clause, value: value)
}
