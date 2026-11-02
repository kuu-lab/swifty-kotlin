private let abi = RuntimeABISectionBuilder("Coroutine")

public extension RuntimeABISpec {
    static let coroutineSuspendedSpec: RuntimeABIFunctionSpec = abi.nt("kk_coroutine_suspended", ret: .opaquePointer)
    static let createCoroutineUninterceptedSpec: RuntimeABIFunctionSpec = abi.nt("kk_create_coroutine_unintercepted", "entryPointRaw completionContinuation")
    static let startCoroutineUninterceptedOrReturnSpec: RuntimeABIFunctionSpec = abi.th("kk_start_coroutine_unintercepted_or_return", "entryPointRaw continuation outThrown")
    static let testScopeCurrentTimeSpec: RuntimeABIFunctionSpec = abi.nt("kk_test_scope_current_time", "scopeHandle")
    static let testSchedulerCurrentTimeSpec: RuntimeABIFunctionSpec = abi.nt("kk_test_scheduler_current_time", "schedulerHandle")
    static let testSchedulerAdvanceTimeBySpec: RuntimeABIFunctionSpec = abi.nt("kk_test_scheduler_advance_time_by", "schedulerHandle delayTimeMillis")
    static let bridgeMutexCreateSpec: RuntimeABIFunctionSpec = abi.th("__kk_mutex_create")
    static let mutexLockSpec: RuntimeABIFunctionSpec = abi.th("kk_mutex_lock", "handle continuation")
    static let mutexUnlockSpec: RuntimeABIFunctionSpec = abi.th("kk_mutex_unlock", "handle outThrown")
    static let bridgeMutexTryLockSpec: RuntimeABIFunctionSpec = abi.th("__kk_mutex_tryLock", "handle")
    static let bridgeMutexIsLockedSpec: RuntimeABIFunctionSpec = abi.th("__kk_mutex_isLocked", "handle")
    static let bridgeMutexHoldsLockSpec: RuntimeABIFunctionSpec = abi.th("__kk_mutex_holdsLock", "handle owner")
    static let bridgeLockWithLockSpec: RuntimeABIFunctionSpec = abi.th("__kk_lock_withLock", "handle actionFnPtr closureRaw outThrown")
    static let semaphoreReleaseSpec: RuntimeABIFunctionSpec = abi.th("kk_semaphore_release", "handle outThrown")

    static let coroutineFunctions: [RuntimeABIFunctionSpec] = [
        coroutineSuspendedSpec,
        abi.nt("kk_coroutine_continuation_new", "functionID"),
        abi.nt("kk_coroutine_current_context"),
        abi.nt("kk_coroutine_call_direct_suspend", "entryPointRaw childContinuation callerContinuationRaw"),
        // KUU-3833: suspendCoroutineUninterceptedOrReturn's block invoke; marks
        // an in-block resume on the continuation state so the suspend call
        // reports suspended instead of returning the delivered result.
        abi.th("kk_suspend_coroutine_orreturn", "blockRaw continuation outThrown"),
        abi.nt("kk_coroutine_child_share_interception", "childContinuation callerContinuationRaw", ret: .void),
        abi.th("kk_coroutine_call_suspend_wrapper", "entryPointRaw continuation outThrown"),
        abi.nt("kk_coroutine_continuation_factory", "contextRaw resumeWithRaw"),
        createCoroutineUninterceptedSpec,
        startCoroutineUninterceptedOrReturnSpec,
        // Link-time markers for the source-backed receiver-less intrinsics. The
        // coroutine lowering pass rewrites calls to them into the entry-point ABI
        // above for known symbols; create markers also accept boxed suspend values.
        abi.nt("kk_create_coroutine_unintercepted_no_receiver", "functionRaw functionContextRaw completionContinuation"),
        abi.th("kk_start_coroutine_unintercepted_or_return_no_receiver", "functionRaw functionContextRaw completionContinuation outThrown"),
        // Link-time markers for the source-backed receiver-bearing intrinsics. The
        // coroutine lowering pass rewrites calls to them into the entry-point ABI
        // above for known symbols; create markers also accept boxed suspend values.
        abi.nt("kk_create_coroutine_unintercepted_with_receiver", "functionRaw functionContextRaw receiverRaw completionContinuation"),
        abi.th("kk_start_coroutine_unintercepted_or_return_with_receiver", "functionRaw functionContextRaw receiverRaw completionContinuation outThrown"),
        abi.nt("kk_coroutine_state_enter", "continuation functionID"),
        abi.nt("kk_coroutine_state_set_label", "continuation label"),
        abi.nt("kk_coroutine_state_exit", "continuation value"),
        abi.nt("kk_coroutine_state_set_spill", "continuation slot value"),
        abi.nt("kk_coroutine_state_get_spill", "continuation slot"),
        abi.nt("kk_coroutine_state_set_completion", "continuation value"),
        abi.nt("kk_coroutine_state_get_completion", "continuation"),
        abi.nt("kk_coroutine_state_get_thrown_exception", "continuation"),
        abi.th("__kk_run_blocking_context", "context fnOrBox env outThrown"),
        abi.th("kk_kxmini_run_blocking", "entryPointRaw functionID outThrown"),
        abi.nt("kk_kxmini_launch", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_async", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_async_await", "handle continuation"),
        abi.nt("kk_kxmini_delay", "milliseconds continuation"),
        abi.nt("kk_coroutine_yield", "continuation"),
        abi.nt("kk_coroutine_launcher_arg_set", "continuation index:int64 value:int64", ret: .int64),
        abi.nt("kk_coroutine_launcher_arg_get", "continuation index:int64", ret: .int64),
        abi.th("kk_kxmini_run_blocking_with_cont", "entryPointRaw continuation outThrown"),
        abi.nt("kk_kxmini_launch_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_kxmini_async_with_cont", "entryPointRaw continuation"),
        abi.th("kk_produce", "entryPointRaw capture0"),
        abi.th("kk_kxmini_produce_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_kxmini_launch_with_dispatcher", "entryPointRaw functionID dispatcherRaw"),
        abi.nt("kk_kxmini_launch_with_dispatcher_and_cont", "entryPointRaw continuation dispatcherRaw"),
        abi.nt("kk_kxmini_launch_lazy", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_launch_lazy_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_kxmini_launch_undispatched", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_launch_undispatched_with_cont", "entryPointRaw continuation"),
        // CoroutineStart.ATOMIC / LAZY / UNDISPATCHED async (STDLIB-CORO-001).
        // The launch family above returns a Job handle; these return a Deferred
        // one carrying the block's result, so each start mode needs its own
        // entry point rather than sharing launch's.
        abi.nt("kk_kxmini_async_atomic", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_async_atomic_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_kxmini_async_lazy", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_async_lazy_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_kxmini_async_undispatched", "entryPointRaw functionID"),
        abi.nt("kk_kxmini_async_undispatched_with_cont", "entryPointRaw continuation"),
        abi.nt("kk_flow_create", "emitterFnPtr continuation"),
        abi.nt("kk_channel_flow_create", "emitterFnPtr continuation"),
        abi.nt("kk_callback_flow_create", "emitterFnPtr continuation"),
        abi.th("kk_flow_emit", "flowHandle value tag outThrown"),
        abi.th("kk_flow_collect", "flowHandle collectorFnPtr collectorEnvPtr continuation outThrown"),
        abi.th("__kk_flow_collectLatest", "flowHandle collectorFnPtr collectorEnvPtr continuation outThrown"),
        abi.nt("__kk_flow_retain", "flowHandle"),
        abi.nt("__kk_flow_release", "flowHandle"),
        // KSP-674: kk_flow_of / kk_flow_empty / kk_flow_as_flow removed —
        // flowOf / emptyFlow / Iterable.asFlow are now Kotlin source composed
        // from kk_flow_create + kk_flow_emit.
        abi.nt("__kk_flow_to_list", "flowHandle continuation"),
        abi.nt("__kk_flow_first", "flowHandle continuation"),
        abi.th("__kk_flow_single", "flowHandle continuation outThrown"),
        abi.th("__kk_flow_zip", "lhsHandle rhsHandle transformFnPtr continuation"),
        abi.th("__kk_flow_combine", "lhsHandle rhsHandle transformFnPtr continuation"),
        abi.th("__kk_flow_merge", "lhsHandle rhsHandle continuation"),
        abi.th("__kk_flow_flat_map_concat", "flowHandle transformFnPtr continuation"),
        abi.th("__kk_flow_flat_map_merge", "flowHandle transformFnPtr continuation"),
        abi.th("__kk_flow_flat_map_latest", "flowHandle transformFnPtr continuation"),
        // flatMapLatestRuntime forwards the suspend transform as a single boxed
        // function value (resolved through runtimeFunctionValueBox /
        // runtimeInvokeSuspendFunction) — no (fnPtr, env) pair is emitted, so
        // this bridge is (flowHandle, mapperFnPtr, outThrown).
        abi.th("__kk_flow_flat_map_latest_external", "flowHandle mapperFnPtr outThrown"),
        abi.th("kk_dispatcher_main"),
        abi.th("__kk_dispatcher_named", "kind"),
        abi.th("__kk_dispatcher_immediate", "dispatcher getterSlot outThrown"),
        // KUU-2687: limitedParallelism view / immediate resolution / Unconfined
        // rejection backing for the bundled CoroutineDispatcher API.
        abi.th("__kk_dispatcher_limited_parallelism", "dispatcher parallelism nameRaw"),
        abi.th("__kk_dispatcher_immediate_or_self", "dispatcher"),
        abi.th("__kk_dispatcher_is_unconfined", "dispatcher"),
        // KUU-3910: CoroutineDispatcher.isDispatchNeeded backing (Unconfined /
        // immediate-on-current-queue answer false; everything else true).
        abi.th("__kk_dispatcher_is_dispatch_needed", "dispatcher"),
        abi.th("__kk_dispatcher_as_executor", "dispatcher outThrown"),
        abi.th("__kk_dispatcher_default_execute", "runnableRaw outThrown"),
        abi.th("__kk_coroutine_new_thread_pool_executor", "nThreads nameRaw scheduled outThrown"),
        abi.th("kk_with_context", "dispatcher blockFnPtr continuation outThrown"),
        abi.th("kk_coroutine_name_create", "nameRaw"),
        abi.th("kk_coroutine_name_get", "handleRaw"),
        abi.th("kk_coroutine_name_key"),
        abi.th("kk_coroutine_name_key_get", "receiver"),
        // KUU-1395: ContinuationInterceptor/CoroutineDispatcher key singletons —
        // the runBlocking event-loop element lookup anchors on these.
        abi.nt("kk_continuation_interceptor_key"),
        abi.nt("kk_coroutine_dispatcher_key"),
        abi.nt("kk_exception_handler_key"),
        abi.th("kk_exception_handler_create", "handlerFnPtr"),
        abi.nt("kk_exception_handler_invoke", "handlerRaw contextRaw exceptionRaw"),
        abi.nt("kk_handle_coroutine_exception", "contextRaw exceptionRaw"),
        abi.nt("kk_context_plus", "leftRaw rightRaw"),
        abi.th("__kk_context_plus_dispatch", "contextRaw otherRaw outThrown"),
        abi.nt("kk_context_get", "contextRaw keyRaw"),
        abi.nt("__kk_is_native_dispatcher", "receiver"),
        abi.nt("__kk_job_is_runtime", "receiver"),
        abi.nt("__kk_dispatcher_default_method", "receiver virtualMethod defaultMethod"),
        abi.th("__kk_context_get_dispatch", "contextRaw keyRaw outThrown"),
        abi.th("kk_context_fold", "contextRaw initial operationFnPtr closureRaw outThrown"),
        abi.nt("kk_context_minusKey", "contextRaw keyRaw"),
        abi.th("__kk_context_minusKey_dispatch", "contextRaw keyRaw outThrown"),
        abi.th("kk_context_get_dispatcher", "contextRaw"),
        abi.th("__kk_continuation_intercepted", "continuationRaw interceptorKey outThrown"),
        abi.th("__kk_start_coroutine_cancellable", "functionRaw completionRaw outThrown", ret: .void),
        abi.th("kk_continuation_interceptor_intercept_continuation", "interceptorRaw continuationRaw"),
        abi.th("kk_with_context_full", "contextRaw blockFnPtr continuation outThrown"),
        abi.th("__kk_channel_await_close", "handle outThrown"),
        abi.th("kk_channel_create", "capacity"),
        // KUU-1404: send on a closed/cancelled channel reports its terminal
        // status through outThrown (ClosedSendChannelException /
        // CancellationException) instead of silently succeeding.
        abi.th("kk_channel_send", "handle value continuation outThrown"),
        abi.nt("__kk_select_try_receive", "handle"),
        abi.nt("__kk_select_builder_exchange", "builder"),
        abi.nt("__kk_select_start_job", "job"),
        abi.nt("__kk_select_builder_current"),
        // KUU-2686: atomic select state/clause handles. Reason code:
        // GC・continuation — selection state lives behind the runtime's
        // claim lock and channel/mutex waiter queues, which Kotlin source
        // cannot reach.
        abi.nt("__kk_select_state_new"),
        abi.nt("__kk_select_clause_new", "state"),
        abi.nt("__kk_select_try_select", "clause"),
        abi.nt("__kk_select_try_select_result", "clause result"),
        abi.nt("__kk_select_mark_selected", "state"),
        abi.nt("__kk_select_selected_clause", "state"),
        abi.nt("__kk_select_state_finish", "state"),
        abi.nt("__kk_select_poll_receive", "handle clause"),
        abi.nt("__kk_select_poll_send", "handle clause value"),
        abi.nt("__kk_select_poll_lock", "handle clause owner"),
        abi.nt("kk_channel_try_send", "handle value"),
        // KUU-1404: receive on a drained-closed/cancelled channel reports its
        // terminal status through outThrown (ClosedReceiveChannelException /
        // CancellationException) instead of returning a default payload.
        abi.th("kk_channel_receive", "handle continuation outValue:nullableIntptrPointer outThrown"),
        RuntimeABIFunctionSpec(
            name: "kk_channel_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine",
            // KSP-678: bridged from bundled Kotlin (Channels.kt) as a plain
            // Int-returning residual; it does not use the outThrown ABI path.
            isThrowing: false
        ),
        // KUU-1404: Channel.cancel() residual bridge; plain Int (0/1) flag
        // like kk_channel_close.
        abi.nt("kk_channel_cancel", "handle"),
        abi.th("kk_channel_is_closed_token", "status"),
        abi.nt("__kk_channel_create_with_policy", "capacity onBufferOverflow"),
        abi.nt("__kk_channel_invoke_on_close", "handle handlerFnPtr handlerClosureRaw"),
        // `kk_channel_try_send` keeps its bare-status contract; the `__kk_`
        // variants return a `RuntimeChannelResultBox` handle.
        abi.nt("__kk_channel_try_receive", "handle"),
        abi.nt("__kk_channel_try_send", "handle value"),
        abi.nt("__kk_channel_receive_catching", "handle"),
        abi.nt("__kk_channel_send_blocking", "handle value"),
        abi.nt("__kk_channel_result_status", "boxRaw"),
        abi.nt("__kk_channel_result_value_or_null", "boxRaw"),
        abi.th("__kk_channel_result_get_or_throw", "boxRaw outThrown"),
        abi.nt("__kk_identity", "value"),
        // Scope-launch used by the bundled produce/actor builders; a suspend
        // block value arrives as the (fnPtr, closureRaw) pair suspend
        // function values use at the ABI boundary (KSP-1573).
        abi.nt("__kk_produce_launch", "channelHandle entryPointRaw closureRaw"),
        // Launcher-continuation counterpart for a suspend literal block:
        // `(channel, launcherThunk, continuation)` mirroring
        // `kk_kxmini_produce_with_cont` (KSP-1573).
        abi.nt("__kk_produce_launch_with_cont", "channelHandle entryPointRaw continuation"),
        // Tags an actor channel so the shared produce launchers register
        // ActorScope, not ProducerScope, as the block receiver's type.
        abi.nt("__kk_actor_scope_mark", "channelHandle"),
        abi.nt("kk_coroutine_scope_async", "scope context start entryPointRaw closureRaw"),
        abi.nt("kk_coroutine_scope_async_with_cont", "scope context start entryPointRaw continuation scopeSlot"),
        abi.nt("__kk_coroutine_scope_launch_context", "scope context start entryPointRaw closureRaw"),
        abi.nt("__kk_coroutine_scope_launch_context_with_cont", "scope context start entryPointRaw continuation scopeSlot"),
        abi.nt("kk_coroutine_scope_new"),
        abi.nt("kk_coroutine_scope_cancel", "scopeHandle"),
        abi.nt("kk_coroutine_scope_fail", "scopeHandle exception"),
        abi.nt("kk_coroutine_scope_wait", "scopeHandle"),
        abi.nt("kk_coroutine_scope_new_with_context", "contextRaw"),
        // KSP-1583: kotlinx.coroutines.test — runTest mints a TestScope over
        // the context and invokes the test body with `this` bound to it.
        // The suspend block value crosses as the (entryPointRaw, closureRaw)
        // pair function-typed parameters use at the ABI boundary; resolvable
        // suspend literals route to the _with_cont launcher variant instead
        // (scope in launcherArgs[0]). outThrown forwards a body-thrown
        // exception to the runTest caller.
        abi.th("kk_test_run_blocking", "contextRaw timeoutRaw entryPointRaw closureRaw outThrown"),
        // KUU-2688: `timeoutRaw` mirrors the boxed variant — the literal path
        // forwards `runTest`'s Duration so the runtime can enforce it.
        abi.th("kk_test_run_blocking_with_cont", "contextRaw timeoutRaw entryPointRaw continuation scopeSlotRaw outThrown"),
        // Lazily minted per-scope TestCoroutineScheduler handle.
        abi.nt("kk_test_scope_scheduler", "scopeHandle"),
        testScopeCurrentTimeSpec,
        abi.nt("kk_test_scheduler_new"),
        testSchedulerCurrentTimeSpec,
        testSchedulerAdvanceTimeBySpec,
        abi.nt("kk_test_scheduler_advance_until_idle", "schedulerHandle"),
        abi.nt("kk_test_scheduler_run_current", "schedulerHandle"),
        // `CoroutineScope.launch { }` (receiver-aware launcher): fire-and-forget like
        // kk_kxmini_launch, so no outThrown parameter -- it returns a Job immediately
        // rather than blocking for the body's result.
        abi.nt("kk_coroutine_scope_launch", "scopeHandle entryPointRaw functionID"),
        // Variant of kk_coroutine_scope_launch that accepts a pre-built continuation
        // carrying the launched suspend lambda's captured outer variables (BUG-049).
        abi.nt("kk_coroutine_scope_launch_with_cont", "scopeHandle entryPointRaw continuation"),
        abi.nt("kk_job_new"),
        abi.nt("__kk_job_bind_wrapper", "wrapper job parent"),
        abi.th("__kk_deferred_get_completed", "handle outThrown"),
        abi.th("__kk_deferred_completion_exception", "handle outThrown"),
        abi.nt("kk_supervisor_job_new"),
        abi.nt("kk_non_cancellable_instance"),
        abi.nt("kk_context_is_active", "contextRaw"),
        abi.th("kk_ensure_active", "outThrown"),
        abi.nt("kk_job_start", "jobHandle", raw: true),
        abi.th("kk_job_join", "jobHandle continuation outThrown"),
        abi.nt("kk_await_cancellation", "continuation"),
        abi.th("kk_job_await_completion", "jobHandle continuation outThrown"),
        abi.nt("__kk_coroutine_scope_context", "handle"),
        abi.nt("__kk_coroutine_scope_is_runtime", "handle"),
        abi.th("kk_coroutine_scope_is_active", "scopeHandle"),
        // STDLIB-CORO-BUG-04: ABI backing for a bare `isActive` reference
        // (no explicit CoroutineScope receiver) inside a coroutine builder body.
        abi.nt("kk_coroutine_current_is_active"),
        abi.nt("kk_coroutine_current_scope"),
        abi.th("kk_coroutine_check_cancellation", "continuation outThrown"),
        abi.th("kk_is_cancellation_exception", "throwableRaw"),
        abi.nt("kk_job_cancel", "jobHandle"),
        abi.nt("kk_job_cancel_with_cause", "jobHandle cause"),
        abi.th("kk_context_cancel", "contextRaw causeRaw"),
        abi.th("kk_context_cancel_no_cause", "contextRaw"),
        abi.nt("kk_job_complete", "jobHandle value"),
        abi.nt("kk_job_complete_unit", "jobHandle"),
        abi.nt("kk_job_complete_exceptionally", "jobHandle exception"),
        abi.nt("kk_job_is_active", "jobHandle"),
        abi.nt("kk_job_is_completed", "jobHandle"),
        abi.nt("kk_job_is_cancelled", "jobHandle"),
        abi.nt("kk_job_get_cancellation_exception", "jobHandle"),
        abi.nt("__kk_job_invoke_on_completion", "jobHandle onCancelling invokeImmediately handlerFnPtr handlerClosureRaw"),
        abi.nt("__kk_job_children", "jobHandle"),
        abi.nt("__kk_job_parent", "jobHandle"),
        // KUU-1386: Job-family members surfaced for real kotlinx `is`/`as`
        // parity — attachChild/childCancelled/parentCancelled bridges and the
        // ChildHandle box accessors.
        abi.nt("kk_job_key"),
        abi.nt("kk_job_key_get", "receiver"),
        abi.nt("__kk_job_attach_to_parent", "jobHandle parentHandle"),
        abi.th("kk_job_get_child_cancellation_cause", "jobHandle outThrown"),
        abi.th("kk_job_parent_cancelled", "jobHandle parentHandle outThrown"),
        abi.nt("kk_job_child_cancelled", "jobHandle cause"),
        abi.nt("kk_job_attach_child", "jobHandle childHandle"),
        abi.nt("kk_child_handle_parent", "handleRaw"),
        abi.nt("kk_child_handle_dispose", "handleRaw"),
        abi.nt("kk_child_handle_child_cancelled", "handleRaw cause"),
        abi.nt("__kk_job_dispose_handle", "jobHandle handlerID", ret: .void),
        abi.nt("kk_context_get_job", "contextRaw"),
        abi.th("kk_coroutine_cancel_current", "message causeRaw"),
        bridgeMutexCreateSpec,

        mutexLockSpec,
        mutexUnlockSpec,
        // KUU-1356: owner-token overloads of Mutex.lock/unlock. The lock
        // bridge takes the caller continuation like kk_mutex_lock plus a
        // trailing outThrown slot so same-owner re-acquisition throws
        // IllegalStateException instead of deadlocking.
        abi.th("__kk_mutex_lock_owner", "handle owner continuation outThrown"),
        abi.th("__kk_mutex_unlock_owner", "handle owner outThrown"),
        bridgeMutexTryLockSpec,
        // KUU-2686: owner-aware tryLock for `Mutex.tryLock(owner)` and
        // `select { onLock(owner) }`. Reason code: GC・continuation — the
        // owner token lives in the runtime mutex handle's waiter state.
        abi.th("__kk_mutex_tryLock_owner", "handle owner outThrown"),
        bridgeMutexIsLockedSpec,
        bridgeMutexHoldsLockSpec,
        // KSP-677: Lock.withLock is Kotlin source delegating to this demoted
        // __kk_lock_withLock bridge; the action is passed via the general
        // closure-taking ABI (function pointer + closure environment + outThrown).
        bridgeLockWithLockSpec,
        abi.th("__kk_semaphore_create", "permits"),
        abi.th("kk_semaphore_acquire", "handle continuation"),
        semaphoreReleaseSpec,
        abi.th("__kk_semaphore_tryAcquire", "handle"),
        abi.th("__kk_semaphore_availablePermits", "handle"),
        // KSP-677: kk_semaphore_withPermit removed — Semaphore.withPermit is Kotlin source.
    ]
}
