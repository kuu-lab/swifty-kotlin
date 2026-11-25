/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-test/common/src/TestDispatcher.kt.
 */
package kotlinx.coroutines.test

import kotlinx.coroutines.ExperimentalCoroutinesApi

// KSP-1583 degraded nominal surface: upstream `TestDispatcher` extends
// `CoroutineDispatcher` and `Delay`, but dispatchers do not reach the runtime
// dispatch path, so the test dispatchers are standalone nominals carrying a
// scheduler and a debug name. Passing one as a coroutine context element does
// not redirect `delay`/`launch` until the dispatcher migration (KSP-1565)
// lands.

@ExperimentalCoroutinesApi
public abstract class TestDispatcher {
    public abstract val scheduler: TestCoroutineScheduler

    internal abstract val name: String?

    public val currentTime: Long
        get() = scheduler.currentTime

    public override fun toString(): String = name ?: "TestDispatcher"
}

@OptIn(ExperimentalCoroutinesApi::class)
private class StandardTestDispatcherImpl(
    override val scheduler: TestCoroutineScheduler,
    override val name: String?
) : TestDispatcher()

@OptIn(ExperimentalCoroutinesApi::class)
private class UnconfinedTestDispatcherImpl(
    override val scheduler: TestCoroutineScheduler,
    override val name: String?
) : TestDispatcher()

@ExperimentalCoroutinesApi
public fun StandardTestDispatcher(
    scheduler: TestCoroutineScheduler? = null,
    name: String? = null
): TestDispatcher = StandardTestDispatcherImpl(scheduler ?: TestCoroutineScheduler(), name)

@ExperimentalCoroutinesApi
public fun UnconfinedTestDispatcher(
    scheduler: TestCoroutineScheduler? = null,
    name: String? = null
): TestDispatcher = UnconfinedTestDispatcherImpl(scheduler ?: TestCoroutineScheduler(), name)

