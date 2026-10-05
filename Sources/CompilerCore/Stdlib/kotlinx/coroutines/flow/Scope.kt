/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Shared.kt>
 * and <kotlinx-coroutines-core/common/src/flow/Channels.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.produce

// KSP-1577: Flow<->coroutine/channel bridging operators as bundled Kotlin
// source, following the same migration pattern as Flow.kt (KSP-499).
//
// `launchIn` is a pure Kotlin composition over the `CoroutineScope.launch`
// builder (kk_coroutine_scope_launch). `produceIn` reuses the `produce { }`
// channel builder (kk_produce); that builder creates its own producer scope,
// so the `scope` argument is accepted for API shape only — the same way a
// user-written `CoroutineScope.produce` extension already ignores `this`.

public fun <T> Flow<T>.launchIn(scope: CoroutineScope): Job {
    val source = this
    return scope.launch {
        source.collect { }
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
public fun <T> Flow<T>.produceIn(scope: CoroutineScope): ReceiveChannel<T> {
    val source = this
    return produce {
        source.collect { value -> send(value) }
    }
}
