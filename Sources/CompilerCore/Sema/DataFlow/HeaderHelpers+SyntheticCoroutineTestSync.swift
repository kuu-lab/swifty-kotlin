/// Extracted from `registerSyntheticCoroutineStubs`
/// (HeaderHelpers+SyntheticCoroutineRegistry.swift). The extracted
/// methods thread the shared registry state through `context` so the
/// call order and side effects are unchanged.

extension DataFlowSemaPhase {
    func registerCoroutineTestStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let coroutinesPkg = context.coroutinesPkg
        let coroutineScopeSymbol = context.coroutineScopeSymbol!
        let coroutineScopeType = context.coroutineScopeType!

        // `TestScope` values are `RuntimeCoroutineScope` handles
        // minted by `kk_coroutine_scope_new_with_context` (via the bundled
        // `TestScope(context)` factory in Stdlib/kotlinx/coroutines/test/),
        // so declaring `CoroutineScope` as a supertype lets the existing
        // synthetic members (`launch`/`cancel`/`isActive`) and Kotlin-source
        // `CoroutineScope` extensions (`produce`/`actor`/`launchIn`) operate
        // on a real scope handle inside `runTest` bodies — the same reason
        // `ProducerScope`-style Kotlin implementations cannot be used here:
        // `kk_coroutine_scope_launch` fatal-errors on non-scope handles.
        //
        // NOTE: this handle has no Kotlin vtable. Members later added to
        // `CoroutineScope` as *source* interface members (e.g.
        // `coroutineContext` in KSP-1582) must not be resolved on TestScope
        // through interface dispatch — keep routing this type's scope
        // operations through the synthetic `kk_coroutine_scope_*` members.
        let testPkg = ensureSyntheticCoroutinePackage(
            coroutinesPkg + [interner.intern("test")],
            symbols: symbols,
            interner: interner
        )
        // `TestCoroutineScheduler` is an opaque handle to a per-scope virtual
        // clock (`RuntimeTestScheduler`). Its `currentTime` and the
        // advance*/runCurrent controls are declared as extensions in
        // Stdlib/kotlinx/coroutines/test/*.kt bridging to the
        // `kk_test_scheduler_*` entry points.
        let testSchedulerSymbol = ensureClassSymbol(
            named: "TestCoroutineScheduler",
            in: testPkg,
            symbols: symbols,
            interner: interner
        )
        let testSchedulerType = types.make(.classType(ClassType(
            classSymbol: testSchedulerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(testSchedulerType, for: testSchedulerSymbol)
        registerSyntheticCoroutineConstructor(
            ownerSymbol: testSchedulerSymbol,
            ownerType: testSchedulerType,
            externalLinkName: "kk_test_scheduler_new",
            parameters: [],
            symbols: symbols,
            interner: interner
        )

        let testScopeSymbol = ensureClassSymbol(
            named: "TestScope",
            in: testPkg,
            symbols: symbols,
            interner: interner
        )
        let testScopeType = types.make(.classType(ClassType(
            classSymbol: testScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(testScopeType, for: testScopeSymbol)
        symbols.setDirectSupertypes([coroutineScopeSymbol], for: testScopeSymbol)
        types.setNominalDirectSupertypes([coroutineScopeSymbol], for: testScopeSymbol)
        registerSyntheticObjectProperty(
            ownerSymbol: testScopeSymbol,
            ownerType: testScopeType,
            name: "testScheduler",
            propertyType: testSchedulerType,
            externalLinkName: "kk_test_scope_scheduler",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticObjectProperty(
            ownerSymbol: testScopeSymbol,
            ownerType: testScopeType,
            name: "currentTime",
            propertyType: types.longType,
            externalLinkName: "kk_test_scope_current_time",
            symbols: symbols,
            interner: interner
        )
        // Degraded backgroundScope: __kk_identity returns the same scope
        // handle, aliasing the test scope itself (still a real
        // RuntimeCoroutineScope) until scopes grow a separately cancellable
        // child list.
        registerSyntheticObjectProperty(
            ownerSymbol: testScopeSymbol,
            ownerType: testScopeType,
            name: "backgroundScope",
            propertyType: coroutineScopeType,
            externalLinkName: "__kk_identity",
            symbols: symbols,
            interner: interner
        )
    }

    func registerCoroutineSyncStubs(context: inout SyntheticCoroutineRegistryContext) {
        let symbols = context.symbols
        let types = context.types
        let interner = context.interner
        let coroutinesPkg = context.coroutinesPkg

        let syncPkg = ensureSyntheticCoroutinePackage(
            coroutinesPkg + [interner.intern("sync")],
            symbols: symbols,
            interner: interner
        )
        let mutexSymbol = ensureInterfaceSymbol(
            named: "Mutex",
            in: syncPkg,
            symbols: symbols,
            interner: interner
        )
        let mutexType = types.make(.classType(ClassType(
            classSymbol: mutexSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(mutexType, for: mutexSymbol)

        // Mutex() factory is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_create bridge.

        let mutexMembers = coroutineMemberRows(of: mutexSymbol, type: mutexType, symbols: symbols, interner: interner)
        mutexMembers.fn("lock", "kk_mutex_lock", ret: types.unitType, isSuspend: true)

        // KUU-1356: upstream `suspend fun lock(owner: Any? = null)` —
        // the owner-token overload bridges to __kk_mutex_lock_owner, which
        // records the token and rejects same-owner re-acquisition.
        mutexMembers.fn("lock", "__kk_mutex_lock_owner", [(name: "owner", type: types.nullableAnyType)], ret: types.unitType, isSuspend: true)
        mutexMembers.fn("unlock", "kk_mutex_unlock", ret: types.unitType)

        // KUU-1356: upstream `fun unlock(owner: Any? = null)` — the owner
        // overload validates the token by identity and throws
        // IllegalStateException on mismatch.
        mutexMembers.fn("unlock", "__kk_mutex_unlock_owner", [(name: "owner", type: types.nullableAnyType)], ret: types.unitType)

        // Mutex.tryLock is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_tryLock bridge.

        // Mutex.isLocked is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_mutex_isLocked bridge.

        // Mutex.withLock is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) as a suspend
        // extension that composes lock()/unlock(); no synthetic stub remains.

        let semaphoreSymbol = ensureInterfaceSymbol(
            named: "Semaphore",
            in: syncPkg,
            symbols: symbols,
            interner: interner
        )
        let semaphoreType = types.make(.classType(ClassType(
            classSymbol: semaphoreSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(semaphoreType, for: semaphoreSymbol)

        // Semaphore(permits) factory is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_create bridge.

        let semaphoreMembers = coroutineMemberRows(of: semaphoreSymbol, type: semaphoreType, symbols: symbols, interner: interner)
        semaphoreMembers.fn("acquire", "kk_semaphore_acquire", ret: types.unitType, isSuspend: true)
        semaphoreMembers.fn("release", "kk_semaphore_release", ret: types.unitType)

        // Semaphore.tryAcquire is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_tryAcquire bridge.

        // Semaphore.availablePermits is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) delegating to the
        // demoted __kk_semaphore_availablePermits bridge.

        // Semaphore.withPermit is migrated to Kotlin source
        // (Stdlib/kotlinx/coroutines/sync/Sync.kt, KSP-677) as a suspend
        // extension that composes acquire()/release(); no synthetic stub remains.
    }
}
