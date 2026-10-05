/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/concurrent/src/channels/Channels.kt>.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_channel_send_blocking")
internal external fun <E> __kkSendChannelBlocking(channel: SendChannel<E>, element: E): ChannelResult<Unit>

public fun <E> SendChannel<E>.trySendBlocking(element: E): ChannelResult<Unit> =
    __kkSendChannelBlocking(this, element)

@KsSymbolName("__kk_channel_send_blocking")
internal external fun <E> __kkChannelBlocking(channel: Channel<E>, element: E): ChannelResult<Unit>

public fun <E> Channel<E>.trySendBlocking(element: E): ChannelResult<Unit> =
    __kkChannelBlocking(this, element)
