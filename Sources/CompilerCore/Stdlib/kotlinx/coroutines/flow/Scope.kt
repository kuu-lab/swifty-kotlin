/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Shared.kt>
 * and <kotlinx-coroutines-core/common/src/flow/Channels.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.produce

// KSP-1577: Flow<->coroutine/channel bridging operators as bundled Kotlin
// source, following the same migration pattern as Flow.kt (KSP-499).
//
// `launchIn` is a pure Kotlin composition over the `CoroutineScope.launch`
// builder (kk_coroutine_scope_launch). `produceIn` delegates to the
// `produce(capacity) { }` channel builder on the given scope (kk_produce);
// the launch still attaches the producer job to the ambient scope rather
// than `scope`'s job, the same limitation `CoroutineScope.produce` has.

public fun <T> Flow<T>.launchIn(scope: CoroutineScope): Job {
    val source = this
    return scope.launch {
        source.collect { }
    }
}

public fun <T> Flow<T>.produceIn(scope: CoroutineScope): ReceiveChannel<T> {
    val source = this
    // Upstream produceIn goes through ChannelFlow.produceImpl, which creates
    // the channel with the default buffered capacity — a rendezvous produce
    // deadlocks the producer (and its parent scope's join) whenever the
    // consumer takes fewer elements than the flow emits (KUU-1415).
    return scope.produce<T>(Channel.BUFFERED) {
        source.collect { value -> send(value) }
    }
}
