/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-test/common/src/TestDispatcher.kt.
 */
package kotlinx.coroutines.test

import kotlinx.coroutines.ExperimentalCoroutinesApi

// KSP-1583 degraded nominal surface: upstream `TestDispatcher` extends
// `CoroutineDispatcher` and `Delay`, but KSwiftK's CoroutineDispatcher is a
// synthetic marker and dispatchers do not reach the runtime dispatch path,
// so the test dispatchers are standalone nominals carrying a scheduler and
// a debug name. Passing one as a coroutine context element does not
// redirect `delay`/`launch` until the dispatcher migration (KSP-1565)
// lands.

/**
 * A test dispatcher connected to a [TestCoroutineScheduler].
 *
 * Degraded (KSP-1583): nominal only — does not implement
 * `CoroutineDispatcher`/`Delay`, so it cannot be installed into a
 * coroutine context yet.
 */
@ExperimentalCoroutinesApi
public abstract class TestDispatcher {
    /** The scheduler that this dispatcher is bound to. */
    public abstract val scheduler: TestCoroutineScheduler

    internal abstract val name: String?

    /** The scheduler's current virtual time, in milliseconds. */
    public val currentTime: Long
        get() = scheduler.currentTime

    public override fun toString(): String = name ?: "TestDispatcher"
}

private class StandardTestDispatcherImpl(
    override val scheduler: TestCoroutineScheduler,
    override val name: String?
) : TestDispatcher()

private class UnconfinedTestDispatcherImpl(
    override val scheduler: TestCoroutineScheduler,
    override val name: String?
) : TestDispatcher()

/**
 * A [TestDispatcher] that queues tasks onto its scheduler (upstream
 * semantics: work scheduled on it does not run eagerly and needs the
 * virtual clock to be advanced).
 *
 * Degraded (KSP-1583): nominal only — carries the scheduler and name but
 * performs no dispatch.
 */
@ExperimentalCoroutinesApi
public fun StandardTestDispatcher(
    scheduler: TestCoroutineScheduler? = null,
    name: String? = null
): TestDispatcher = StandardTestDispatcherImpl(scheduler ?: TestCoroutineScheduler(), name)

/**
 * A [TestDispatcher] that runs work eagerly (upstream semantics: tasks on
 * it execute immediately rather than queueing on the scheduler).
 *
 * Degraded (KSP-1583): nominal only — carries the scheduler and name but
 * performs no dispatch.
 */
@ExperimentalCoroutinesApi
public fun UnconfinedTestDispatcher(
    scheduler: TestCoroutineScheduler? = null,
    name: String? = null
): TestDispatcher = UnconfinedTestDispatcherImpl(scheduler ?: TestCoroutineScheduler(), name)

/**
 * Marker matching upstream `DelayWithTimeoutDiagnostics : Delay`, which
 * reports the last timeout diagnostics on a delay-timeout failure. `Delay`
 * has no bundled declaration yet (KSP-1566), so this is a nominal marker.
 */
internal interface DelayWithTimeoutDiagnostics
