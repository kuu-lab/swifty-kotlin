/*
 * Copyright 2016-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx.coroutines channel builder APIs.
 */

package kotlinx.coroutines.channels

import kotlinx.coroutines.CoroutineScope

// KSP-1543: ProducerScope is the receiver exposed by channelFlow and
// callbackFlow. The object is backed by the runtime channel created for each
// collection; the member operations keep the public Kotlin shape while
// retaining the channel ABI at the boundary.
//
// KSP-1571: `SendChannel` moved to Channel.kt and `ChannelResult` to
// ChannelResult.kt to match the upstream file layout.

public interface ProducerScope<in E> : CoroutineScope, SendChannel<E>
