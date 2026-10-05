/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/channels/Produce.kt>.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi

@KsSymbolName("__kk_channel_await_close")
internal external fun __kkChannelAwaitClose(scope: ProducerScope<*>)

public suspend fun ProducerScope<*>.awaitClose(block: () -> Unit = {}) {
    try {
        __kkChannelAwaitClose(this)
    } finally {
        block()
    }
}

// `SendChannel.isClosedForSend` lives in Channel.kt with the rest of the
// channel closed-state surface (KSP-1571). A second same-name extension here
// shadows the Channel.kt one for `this.isClosedForSend` inside ProducerScope
// blocks (bundled-extension registration dedupe), so only one declaration may
// exist.

// KSP-1573: `CoroutineScope.produce` is composed from a channel plus a
// scope-launch of the producer block. Kotlin source cannot invoke a suspend
// receiver-typed lambda (`ProducerScope<E>.() -> Unit`) directly, so the
// launch itself is a runtime entry point: it registers the child job on the
// ambient coroutine scope, binds the channel as the block's `this` (the same
// launcherArgs[0] convention the synthetic kk_produce path used), and closes
// the channel when the block finishes. `produce` returns the channel itself
// as the ReceiveChannel.

@KsSymbolName("__kk_produce_launch")
private external fun <E> __kkProduceLaunch(
    channel: Channel<E>,
    block: suspend ProducerScope<E>.() -> Unit
): Channel<E>

@ExperimentalCoroutinesApi
public fun <E> CoroutineScope.produce(
    block: suspend ProducerScope<E>.() -> Unit
): ReceiveChannel<E> = produce(0, block)

@ExperimentalCoroutinesApi
public fun <E> CoroutineScope.produce(
    capacity: Int = 0,
    block: suspend ProducerScope<E>.() -> Unit
): ReceiveChannel<E> {
    val channel = Channel<E>(capacity)
    __kkProduceLaunch(channel, block)
    return channel
}
