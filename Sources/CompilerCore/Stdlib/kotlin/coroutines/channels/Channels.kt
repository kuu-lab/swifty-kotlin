package kotlinx.coroutines.channels

// KSP-678
// Channel (b) surface migrated to bundled Kotlin source (7 functions): the
// Channel() / Channel(capacity) factories, close, the isClosedForSend /
// isClosedForReceive queries, and the whole iterator layer (iterator,
// ChannelIterator.hasNext, ChannelIterator.next). Each delegates to a residual
// runtime bridge via @KsSymbolName; the runtime entry points are retained
// (c-soft) and continue to model the blocking/suspend behaviour.
//
// The suspension core stays in Swift as c-soft residual (3 functions): send,
// receive, and the internal kk_channel_is_closed_token status classifier used
// by the send/receive result codes.
//
// Migration source: Sources/Runtime/RuntimeCoroutineChannel.swift
//   kk_channel_create, kk_channel_close, kk_channel_is_closed_for_send,
//   kk_channel_is_closed_for_receive, kk_channel_iterator,
//   kk_channel_iterator_hasNext, kk_channel_iterator_next

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_channel_create")
private external fun <T> __kkChannelCreate(capacity: Int): Channel<T>

// Channel() is a rendezvous channel (capacity 0); Channel(capacity) is buffered.
// Two explicit overloads mirror the previous synthetic factory bridges.
public fun <T> Channel(): Channel<T> = __kkChannelCreate(0)

public fun <T> Channel(capacity: Int): Channel<T> = __kkChannelCreate(capacity)

// The residual runtime bridges return an Int flag (0/1); convert to Boolean in
// Kotlin so the ABI return width matches the c-soft `@_cdecl` signatures.
@KsSymbolName("kk_channel_close")
private external fun Channel<*>.__kkChannelClose(): Int

@KsSymbolName("kk_channel_is_closed_for_send")
private external fun Channel<*>.__kkChannelIsClosedForSend(): Int

@KsSymbolName("kk_channel_is_closed_for_receive")
private external fun Channel<*>.__kkChannelIsClosedForReceive(): Int

public fun Channel<*>.close(): Boolean = this.__kkChannelClose() != 0

// NOTE: extension *properties* use a star-projected `Channel<*>` receiver
// because the parser does not accept type parameters on extension properties.
public val Channel<*>.isClosedForSend: Boolean
    get() = this.__kkChannelIsClosedForSend() != 0

public val Channel<*>.isClosedForReceive: Boolean
    get() = this.__kkChannelIsClosedForReceive() != 0

// Iterator layer. `Channel<T>.iterator()` returns a ChannelIterator<T> runtime
// handle; hasNext() performs the blocking receive (delegating to the retained
// runtime bridge) and next() returns the value peeked by the last hasNext().
// Star-projected receivers mirror the close()/isClosed* extensions above: the
// loop variable's element type is recovered from the Channel<T> being iterated,
// not from next()'s declared return, so these do not need to thread <T>.
@KsSymbolName("kk_channel_iterator")
private external fun Channel<*>.__kkChannelIterator(): ChannelIterator<*>

@KsSymbolName("kk_channel_iterator_hasNext")
private external fun ChannelIterator<*>.__kkChannelIteratorHasNext(): Int

@KsSymbolName("kk_channel_iterator_next")
private external fun ChannelIterator<*>.__kkChannelIteratorNext(): Any?

public operator fun Channel<*>.iterator(): ChannelIterator<*> =
    this.__kkChannelIterator()

public operator fun ChannelIterator<*>.hasNext(): Boolean =
    this.__kkChannelIteratorHasNext() != 0

public operator fun ChannelIterator<*>.next(): Any? =
    this.__kkChannelIteratorNext()
