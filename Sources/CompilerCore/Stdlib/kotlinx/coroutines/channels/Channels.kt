/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/concurrent/src/channels/Channels.kt>.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_channel_send")
internal external fun <E> __kkSendChannelBlocking(channel: SendChannel<E>, element: E, continuation: Int): Int

public fun <E> SendChannel<E>.trySendBlocking(element: E): ChannelResult<Unit> =
    ChannelResult<Unit>(__kkSendChannelBlocking(this, element, 0))

@KsSymbolName("kk_channel_send")
internal external fun <E> __kkChannelBlocking(channel: Channel<E>, element: E, continuation: Int): Int

public fun <E> Channel<E>.trySendBlocking(element: E): ChannelResult<Unit> =
    ChannelResult<Unit>(__kkChannelBlocking(this, element, 0))
