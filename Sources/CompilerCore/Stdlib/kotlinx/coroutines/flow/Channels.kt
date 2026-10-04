/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines <kotlinx-coroutines-core/common/src/flow/Channels.kt>.
 */

package kotlinx.coroutines.flow

import kotlinx.coroutines.channels.ReceiveChannel
import kotlinx.coroutines.channels.close
import kotlinx.coroutines.channels.iterator
import kotlinx.coroutines.channels.hasNext
import kotlinx.coroutines.channels.next

@Suppress("UNCHECKED_CAST")
public fun <T> ReceiveChannel<T>.receiveAsFlow(): Flow<T> {
    val channel = this
    return flow {
        val iterator = channel.iterator()
        while (iterator.hasNext()) emit(iterator.next() as T)
    }
}

// ReceiveChannel is a Channel alias here and has no cancellation API. Close
// in finally for cleanup; unlike receiveAsFlow, allow only one collection.
@Suppress("UNCHECKED_CAST")
public fun <T> ReceiveChannel<T>.consumeAsFlow(): Flow<T> {
    val channel = this
    var consumed = false
    return flow {
        check(!consumed) { "ReceiveChannel.consumeAsFlow can be collected just once" }
        consumed = true
        try {
            val iterator = channel.iterator()
            while (iterator.hasNext()) emit(iterator.next() as T)
        } finally {
            channel.close()
        }
    }
}
