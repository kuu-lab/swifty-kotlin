/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-test/common/src/TestBuilders.kt.
 */
package kotlinx.coroutines.test

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi

// KSP-1583: `runTest` is extern so the trailing suspend lambda resolves at
// the call site: a literal is rewritten by CoroutineLoweringPass into the
// launcher-continuation convention (`kk_test_run_blocking_with_cont`, scope
// in launcherArgs[0]); a block held in a variable crosses as the (fnPtr,
// env) pair suspend function values use at the ABI boundary, and the
// runtime invokes it with the minted TestScope bound as the receiver.

/**
 * Mirror of the upstream `TestResult`: the actual type used on the JVM is
 * `Unit`, so this is a `Unit` alias here (same upstream source shape as
 * `CoroutineException` — see kotlinx-coroutines 1.10.x upstream note).
 */
public typealias TestResult = Unit

/**
 * Executes [testBody] as a test coroutine: creates a [TestScope], runs the
 * body on it, and waits for it to complete.
 *
 * Delays in the test scope use virtual time, and remaining scheduled child
 * work is advanced before this function returns. [timeout] is accepted for
 * signature compatibility but is not enforced.
 */
@ExperimentalCoroutinesApi
@KsSymbolName("kk_test_run_blocking")
public external fun runTest(
    context: CoroutineContext = EmptyCoroutineContext,
    timeout: Duration = 60.seconds,
    testBody: suspend TestScope.() -> Unit
): TestResult
