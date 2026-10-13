/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines `Actor.kt`.
 */

package kotlinx.coroutines.channels

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ObsoleteCoroutinesApi

// KSP-1573: `CoroutineScope.actor` mirrors `produce` with the roles reversed:
// the builder launches a consumer coroutine and hands the mailbox channel to
// the caller as a SendChannel. `ActorScope.channel` exposes the channel the
// actor should consume; the handle is the same runtime object underneath.
// The launch shares `__kk_produce_launch` with produce — an ActorScope is a
// channel-backed CoroutineScope exactly like ProducerScope.

@KsSymbolName("__kk_identity")
@OptIn(ObsoleteCoroutinesApi::class)
private external fun <E> __kkActorScopeChannel(scope: ActorScope<E>): Channel<E>

@KsSymbolName("__kk_identity")
private external fun <E> __kkAsSendChannel(channel: Channel<E>): SendChannel<E>

@KsSymbolName("__kk_coroutine_scope_context")
private external fun __kkActorScopeContext(scope: Any): CoroutineContext

// ActorScope is a class so `channel` resolves through static member
// dispatch: the receiver handed to the launched block is the channel handle
// itself, which owns no Kotlin itable — an interface member getter would
// emit a virtual call the handle cannot serve.
@ObsoleteCoroutinesApi
public class ActorScope<E> : CoroutineScope {
    public override val coroutineContext: CoroutineContext
        get() = __kkActorScopeContext(this)

    /** The mailbox channel this actor consumes; identical to the SendChannel
     *  returned to the builder's caller. */
    public val channel: Channel<E>
        get() = __kkActorScopeChannel(this)
}

@KsSymbolName("__kk_produce_launch")
@OptIn(ObsoleteCoroutinesApi::class)
private external fun <E> __kkActorLaunch(
    channel: Channel<E>,
    block: suspend ActorScope<E>.() -> Unit
): Channel<E>

// Two overloads, not a `capacity = 0` default: a defaulted `actor {}` call
// resolves to `actor$default`, a real forwarder function whose `block`
// parameter is a suspend function *value* — the literal's captures can't
// cross that boundary (the env slot is empty), so the boxed
// `__kk_produce_launch` path has nothing to pass to the launcher thunk.
// `actor { }` must instead bind `actor(block)` and inline-expand at the
// call site, the same shape produce uses.
@ObsoleteCoroutinesApi
public fun <E> CoroutineScope.actor(
    block: suspend ActorScope<E>.() -> Unit
): SendChannel<E> = actor(0, block)

@ObsoleteCoroutinesApi
public fun <E> CoroutineScope.actor(
    capacity: Int,
    block: suspend ActorScope<E>.() -> Unit
): SendChannel<E> {
    val channel = Channel<E>(capacity)
    __kkActorLaunch(channel, block)
    return __kkAsSendChannel(channel)
}
