/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/channels/BroadcastChannel.kt.
 * The upstream implementation is a BufferedChannel subclass; here each
 * subscription is an ordinary runtime-backed Channel and the broadcast fans
 * out through the public Channel member surface.
 */

package kotlinx.coroutines.channels

import kotlin.coroutines.cancellation.CancellationException
import kotlinx.atomicfu.locks.SynchronizedObject
import kotlinx.atomicfu.locks.synchronized
import kotlinx.coroutines.InternalCoroutinesApi
import kotlinx.coroutines.ObsoleteCoroutinesApi
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive

private const val CHANNEL_DEFAULT_CAPACITY = 64

@ObsoleteCoroutinesApi
public interface BroadcastChannel<E> : SendChannel<E> {
    public fun openSubscription(): ReceiveChannel<E>

    public fun cancel(cause: CancellationException? = null)
}

@ObsoleteCoroutinesApi
public fun <E> BroadcastChannel(capacity: Int): BroadcastChannel<E> = when (capacity) {
    0 -> throw IllegalArgumentException("Unsupported 0 capacity for BroadcastChannel")
    Channel.UNLIMITED -> throw IllegalArgumentException("Unsupported UNLIMITED capacity for BroadcastChannel")
    Channel.CONFLATED -> ConflatedBroadcastChannel()
    Channel.BUFFERED -> BroadcastChannelImpl(CHANNEL_DEFAULT_CAPACITY)
    else -> BroadcastChannelImpl(capacity)
}

@OptIn(ObsoleteCoroutinesApi::class, InternalCoroutinesApi::class)
internal class BroadcastChannelImpl<E>(
    val capacity: Int
) : BroadcastChannel<E> {

    init {
        require(capacity >= 1 || capacity == Channel.CONFLATED) {
            "BroadcastChannel capacity must be positive or Channel.CONFLATED, but $capacity was specified"
        }
    }

    private val lock = SynchronizedObject()
    private var subscribers: List<Channel<E>> = emptyList()
    private var closedForSend = false
    private var closeCause: Throwable? = null
    private var hasLastElement = false
    private var lastElement: Any? = null

    private val isConflated: Boolean
        get() = capacity == Channel.CONFLATED

    override fun openSubscription(): ReceiveChannel<E> {
        val subscriber = Channel<E>(capacity)
        synchronized(lock) {
            if (closedForSend) {
                subscriber.close(closeCause)
                return subscriber
            }
            if (isConflated && hasLastElement) {
                @Suppress("UNCHECKED_CAST")
                subscriber.trySend(lastElement as E)
            }
            subscribers = subscribers + subscriber
        }
        return subscriber
    }

    private fun removeSubscriber(subscriber: Channel<E>) {
        synchronized(lock) {
            subscribers = subscribers.filter { it !== subscriber }
        }
    }

    override suspend fun send(element: E) {
        val targets = synchronized(lock) {
            if (closedForSend) throw ClosedSendChannelException("Channel was closed")
            if (isConflated) {
                hasLastElement = true
                lastElement = element
            }
            subscribers.toList()
        }
        for (subscriber in targets) {
            if (subscriber.isClosedForSend) {
                removeSubscriber(subscriber)
                continue
            }
            try {
                subscriber.send(element)
            } catch (e: ClosedSendChannelException) {
                removeSubscriber(subscriber)
            } catch (e: CancellationException) {
                if (!currentCoroutineContext().isActive) throw e
                removeSubscriber(subscriber)
            }
        }
    }

    override fun trySend(element: E): ChannelResult<Unit> {
        return synchronized(lock) {
            if (closedForSend) return ChannelResult.closed(closeCause)
            if (isConflated) {
                hasLastElement = true
                lastElement = element
            }
            var failed = false
            val dead = mutableListOf<Channel<E>>()
            for (subscriber in subscribers) {
                if (subscriber.isClosedForSend) {
                    dead.add(subscriber)
                    continue
                }
                val result = subscriber.trySend(element)
                if (result.isClosed || result.isFailure) {
                    dead.add(subscriber)
                    failed = true
                }
            }
            if (dead.isNotEmpty()) subscribers = subscribers - dead.toSet()
            if (failed) ChannelResult.failure() else ChannelResult.success(Unit)
        }
    }

    override fun close(): Boolean = close(null)

    override fun close(cause: Throwable?): Boolean {
        val targets = synchronized(lock) {
            if (closedForSend) return false
            closedForSend = true
            closeCause = cause
            val current = subscribers
            subscribers = emptyList()
            current
        }
        for (subscriber in targets) {
            subscriber.close(cause)
        }
        return true
    }

    override fun cancel(cause: CancellationException?) {
        val targets = synchronized(lock) {
            if (closedForSend) return
            closedForSend = true
            closeCause = cause
            val current = subscribers
            subscribers = emptyList()
            current
        }
        for (subscriber in targets) {
            subscriber.cancel(cause)
        }
    }

    override val isClosedForSend: Boolean
        get() = synchronized(lock) { closedForSend }

    @Suppress("UNCHECKED_CAST")
    val value: E
        get() = synchronized(lock) {
            if (closedForSend) throw ClosedSendChannelException("This broadcast channel is closed")
            if (!hasLastElement) error("No value")
            lastElement as E
        }

    @Suppress("UNCHECKED_CAST")
    val valueOrNull: E?
        get() = synchronized(lock) {
            if (closedForSend || !hasLastElement) null else lastElement as E
        }
}

@ObsoleteCoroutinesApi
public class ConflatedBroadcastChannel<E> private constructor(
    private val broadcast: BroadcastChannelImpl<E>
) : BroadcastChannel<E> {

    @ObsoleteCoroutinesApi
    public constructor() : this(newConflatedBroadcastImpl())

    @ObsoleteCoroutinesApi
    public constructor(value: E) : this() {
        trySend(value)
    }

    override fun openSubscription(): ReceiveChannel<E> = broadcast.openSubscription()

    override fun cancel(cause: CancellationException?) = broadcast.cancel(cause)

    override suspend fun send(element: E) = broadcast.send(element)

    override fun trySend(element: E): ChannelResult<Unit> = broadcast.trySend(element)

    override fun close(): Boolean = broadcast.close()

    override fun close(cause: Throwable?): Boolean = broadcast.close(cause)

    override val isClosedForSend: Boolean
        get() = broadcast.isClosedForSend

    public val value: E
        get() = broadcast.value

    public val valueOrNull: E?
        get() = broadcast.valueOrNull
}

@OptIn(ObsoleteCoroutinesApi::class, InternalCoroutinesApi::class)
private fun <E> newConflatedBroadcastImpl(): BroadcastChannelImpl<E> =
    BroadcastChannelImpl(Channel.CONFLATED)
