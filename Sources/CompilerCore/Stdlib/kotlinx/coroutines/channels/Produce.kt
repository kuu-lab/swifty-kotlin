/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/channels/Produce.kt>.
 */

package kotlinx.coroutines.channels

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_channel_await_close")
internal external fun __kkChannelAwaitClose(scope: ProducerScope<*>)

public suspend fun ProducerScope<*>.awaitClose(block: () -> Unit = {}) {
    try {
        __kkChannelAwaitClose(this)
    } finally {
        block()
    }
}

@KsSymbolName("kk_channel_is_closed_for_send")
internal external fun __kkSendChannelIsClosedForSend(channel: SendChannel<*>): Int

public val SendChannel<*>.isClosedForSend: Boolean
    get() = __kkSendChannelIsClosedForSend(this) != 0
