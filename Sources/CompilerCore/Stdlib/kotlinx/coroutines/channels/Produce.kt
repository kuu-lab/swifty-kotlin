/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines `Produce.kt`.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope

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

public fun <E> CoroutineScope.produce(
    block: suspend ProducerScope<E>.() -> Unit
): ReceiveChannel<E> = produce(0, block)

public fun <E> CoroutineScope.produce(
    capacity: Int = 0,
    block: suspend ProducerScope<E>.() -> Unit
): ReceiveChannel<E> {
    val channel = Channel<E>(capacity)
    __kkProduceLaunch(channel, block)
    return channel
}
