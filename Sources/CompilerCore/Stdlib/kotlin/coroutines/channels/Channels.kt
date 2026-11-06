package kotlinx.coroutines.channels

// Migration source: Sources/Runtime/RuntimeCoroutineChannel.swift
//   kk_channel_create, kk_channel_iterator,
//   kk_channel_iterator_hasNext, kk_channel_iterator_next
// KUU-4072: close/cancel/isClosedForSend/isClosedForReceive are
// Channel/SendChannel interface members now (Stdlib/kotlinx/coroutines/
// channels/Channel.kt) and bridge to the kk_channel_* entry points directly.

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_channel_create")
private external fun <T> __kkChannelCreate(capacity: Int): Channel<T>

// Two explicit overloads mirror the previous synthetic factory bridges.
// Negative `Channel.Factory` sentinels (CONFLATED -1, BUFFERED -2) keep their
// kotlinx semantics: the runtime resolves them inside kk_channel_create.
// Capacity < -2 throws IllegalArgumentException like upstream (KUU-1403).
public fun <T> Channel(): Channel<T> = __kkChannelCreate(0)

// Upstream `Channel(capacity)` is `Channel(capacity, BufferOverflow.SUSPEND)`:
// the Channel.Factory sentinels (RENDEZVOUS / CONFLATED / BUFFERED /
// UNLIMITED) are valid capacity arguments, so this factory
// delegates to the policy-aware bridge instead of letting kk_channel_create
// clamp negatives to a rendezvous channel (KUU-1415: Channel(Channel.BUFFERED)
// and produce(capacity = Channel.BUFFERED) silently produced capacity 0).
// OPTIONAL_CHANNEL (-3) is internal-only upstream and is rejected by the
// policy-aware factory's require(capacity >= -2) like a raw negative.
public fun <T> Channel(capacity: Int): Channel<T> =
    Channel(capacity, BufferOverflow.SUSPEND)

// The runtime throws the closed-channel exceptions from send()/receive() when
// the channel reaches a terminal closed state, so the classes are also
// user-visible for typed `catch` clauses. Runtime-allocated boxes preserve the
// exact throwable identity, matching the CancellationException source-backing
// pattern (KSP-1150).
// JVM parity (kotlinx-coroutines 1.10.2): ClosedReceiveChannelException
// extends NoSuchElementException, ClosedSendChannelException extends
// IllegalStateException.
public class ClosedReceiveChannelException : NoSuchElementException {
    @KsSymbolName("__kk_closed_receive_channel_exception_new_message")
    public constructor(message: String?)
}

public class ClosedSendChannelException : IllegalStateException {
    @KsSymbolName("__kk_closed_send_channel_exception_new_message")
    public constructor(message: String?)
}

// hasNext() performs the blocking receive and next() returns the value peeked
// by the last hasNext(). Preserve the channel element type through the
// iterator so both for-loops and direct next() calls retain their types.
// KUU-4072: `iterator()` stays an extension — a Channel interface member
// returning `ChannelIterator<E>` loses the class type argument during member
// substitution, which breaks the for-loop hasNext()/next() convention lookup.
@KsSymbolName("kk_channel_iterator")
private external fun <E> Channel<E>.__kkChannelIterator(): ChannelIterator<E>

@KsSymbolName("kk_channel_iterator_hasNext")
private external fun ChannelIterator<*>.__kkChannelIteratorHasNext(): Int

@KsSymbolName("kk_channel_iterator_next")
private external fun <E> ChannelIterator<E>.__kkChannelIteratorNext(): E

public operator fun <E> Channel<E>.iterator(): ChannelIterator<E> =
    this.__kkChannelIterator()

public operator fun ChannelIterator<*>.hasNext(): Boolean =
    this.__kkChannelIteratorHasNext() != 0

public operator fun <E> ChannelIterator<E>.next(): E =
    this.__kkChannelIteratorNext()
