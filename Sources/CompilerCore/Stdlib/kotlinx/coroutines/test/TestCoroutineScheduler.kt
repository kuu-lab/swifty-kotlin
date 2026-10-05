/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-test/common/src/TestCoroutineScheduler.kt.
 */
package kotlinx.coroutines.test

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.ExperimentalCoroutinesApi

// KSP-1583: TestCoroutineScheduler is an opaque runtime-handle type (see
// HeaderHelpers+SyntheticCoroutineRegistry.swift): the clock lives in
// `RuntimeTestScheduler` because scheduler state must be reachable through
// a TestScope handle, and extension properties cannot carry per-receiver
// state. Phase 1 is only a virtual `currentTime` counter — there is no
// task queue, so `advanceUntilIdle`/`runCurrent` are degraded no-ops and
// children launched inside `runTest` run on the real event loop (virtual
// time is rounded to real time).

@KsSymbolName("kk_test_scheduler_current_time")
private external fun kkTestSchedulerCurrentTime(scheduler: TestCoroutineScheduler): Long

@KsSymbolName("kk_test_scheduler_advance_time_by")
private external fun kkTestSchedulerAdvanceTimeBy(scheduler: TestCoroutineScheduler, delayTimeMillis: Long)

@KsSymbolName("kk_test_scheduler_advance_until_idle")
private external fun kkTestSchedulerAdvanceUntilIdle(scheduler: TestCoroutineScheduler)

@KsSymbolName("kk_test_scheduler_run_current")
private external fun kkTestSchedulerRunCurrent(scheduler: TestCoroutineScheduler)

/** The current virtual time in milliseconds, as tracked by this scheduler. */
@ExperimentalCoroutinesApi
public val TestCoroutineScheduler.currentTime: Long
    get() = kkTestSchedulerCurrentTime(this)

/**
 * Advances the virtual clock by [delayTimeMillis] milliseconds.
 *
 * Degraded (KSP-1583): with no virtual-time task queue this is a pure clock
 * advance; nothing is scheduled to run at the new time.
 */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.advanceTimeBy(delayTimeMillis: Long) {
    if (delayTimeMillis < 0) {
        throw IllegalArgumentException("advanceTimeBy called with a negative delayTimeMillis: $delayTimeMillis")
    }
    kkTestSchedulerAdvanceTimeBy(this, delayTimeMillis)
}

/** Degraded (KSP-1583): no scheduled task queue exists yet, so this is a no-op. */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.advanceUntilIdle() = kkTestSchedulerAdvanceUntilIdle(this)

/** Degraded (KSP-1583): no scheduled task queue exists yet, so this is a no-op. */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.runCurrent() = kkTestSchedulerRunCurrent(this)
