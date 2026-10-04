/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-test/common/src/TestScope.kt.
 */
package kotlinx.coroutines.test

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi

// KSP-1583: TestScope is an opaque runtime-handle type whose values are
// RuntimeCoroutineScope handles (HeaderHelpers+SyntheticCoroutineRegistry).
// That is what makes `launch {}`/`cancel()`/`isActive` inside a `runTest`
// body safe: the synthetic `kk_coroutine_scope_*` members fatal-error on
// anything that is not a real scope, so a Kotlin-object TestScope would
// crash on the first builder call.
//
// `testScheduler`, `currentTime` and `backgroundScope` are registered as
// synthetic member *properties* on the handle type (upstream declares them
// `val TestScope.x` extensions): extension properties do not resolve on the
// implicit suspend-lambda receiver — they emit a `kk_global_root_slot_*`
// load for a slot that is never defined — while member properties route
// through the same `kk_` bridge as `isActive`. The surface syntax is
// identical either way. `backgroundScope` is degraded to an alias of the
// test scope itself (`__kk_identity` returns the same handle) until scopes
// grow a separately cancellable child list.

@KsSymbolName("kk_coroutine_scope_new_with_context")
private external fun kkTestScopeNewWithContext(context: CoroutineContext): TestScope

/**
 * Creates a scope for test coroutines.
 *
 * Degraded (KSP-1583): the scope is a plain RuntimeCoroutineScope; the
 * [context] is stored but the extra context elements upstream installs
 * (a TestDispatcher bound to the scheduler, a CollectorJob) do not exist.
 */
@ExperimentalCoroutinesApi
public fun TestScope(context: CoroutineContext = EmptyCoroutineContext): TestScope =
    kkTestScopeNewWithContext(context)

/** Advances the virtual clock by [delayTimeMillis] and runs work scheduled for the new time. */
@ExperimentalCoroutinesApi
public fun TestScope.advanceTimeBy(delayTimeMillis: Long) {
    testScheduler.advanceTimeBy(delayTimeMillis)
    testScheduler.runCurrent()
}

/** Runs all enqueued work, advancing the clock as needed (degraded: no-op, KSP-1583). */
@ExperimentalCoroutinesApi
public fun TestScope.advanceUntilIdle() = testScheduler.advanceUntilIdle()

/** Runs the work scheduled for the current virtual time (degraded: no-op, KSP-1583). */
@ExperimentalCoroutinesApi
public fun TestScope.runCurrent() = testScheduler.runCurrent()
