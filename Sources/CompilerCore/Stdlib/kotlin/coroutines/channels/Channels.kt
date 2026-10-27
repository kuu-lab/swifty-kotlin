package kotlinx.coroutines.channels

// Migration source: Sources/Runtime/RuntimeCoroutineChannel.swift
//   kk_channel_create, kk_channel_close, kk_channel_is_closed_for_send,
//   kk_channel_is_closed_for_receive, kk_channel_iterator,
//   kk_channel_iterator_hasNext, kk_channel_iterator_next

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

// The residual runtime bridges return an Int flag (0/1); convert to Boolean in
// Kotlin so the ABI return width matches the c-soft `@_cdecl` signatures.
@KsSymbolName("kk_channel_close")
private external fun Channel<*>.__kkChannelClose(): Int

@KsSymbolName("kk_channel_is_closed_for_send")
private external fun Channel<*>.__kkChannelIsClosedForSend(): Int

@KsSymbolName("kk_channel_is_closed_for_receive")
private external fun Channel<*>.__kkChannelIsClosedForReceive(): Int

public fun Channel<*>.close(): Boolean = this.__kkChannelClose() != 0

// Cancels the channel, discards pending elements, and makes subsequent
// send()/receive() fail with CancellationException instead of a default payload.
@KsSymbolName("kk_channel_cancel")
private external fun Channel<*>.__kkChannelCancel(): Int

public fun Channel<*>.cancel() {
    this.__kkChannelCancel()
}

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

// NOTE: extension *properties* use a star-projected `Channel<*>` receiver
// because the parser does not accept type parameters on extension properties.
public val Channel<*>.isClosedForSend: Boolean
    get() = this.__kkChannelIsClosedForSend() != 0

public val Channel<*>.isClosedForReceive: Boolean
    get() = this.__kkChannelIsClosedForReceive() != 0

// hasNext() performs the blocking receive and next() returns the value peeked
// by the last hasNext(). Preserve the channel element type through the
// iterator so both for-loops and direct next() calls retain their types.
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
