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
// HeaderHelpers+SyntheticCoroutineRegistry.swift): the clock and scheduled
// task queue live in `RuntimeTestScheduler` because scheduler state must be
// reachable through a TestScope handle, and extension properties cannot
// carry per-receiver state.

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
 * Runs scheduled work before the target time while advancing the virtual
 * clock. Work scheduled exactly at the target time remains queued.
 */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.advanceTimeBy(delayTimeMillis: Long) {
    if (delayTimeMillis < 0) {
        throw IllegalArgumentException("advanceTimeBy called with a negative delayTimeMillis: $delayTimeMillis")
    }
    kkTestSchedulerAdvanceTimeBy(this, delayTimeMillis)
}

/** Runs all queued work, advancing virtual time until no work remains. */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.advanceUntilIdle() = kkTestSchedulerAdvanceUntilIdle(this)

/** Runs the work scheduled for the current virtual time. */
@ExperimentalCoroutinesApi
public fun TestCoroutineScheduler.runCurrent() = kkTestSchedulerRunCurrent(this)
