/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/Timeout.kt.
 */
package kotlinx.coroutines

import kotlin.internal.KsSymbolName
import kotlin.time.Duration

// KSP-1566 (KUU-902): `withTimeout` / `withTimeoutOrNull` were synthetic
// top-level stubs; they are bundled Kotlin now, mirroring upstream
// `Timeout.kt`.
//
// Every overload is declared directly on the runtime bridge:
// `kk_with_timeout` throws TimeoutCancellationException through the
// `outThrown` channel on expiry, `kk_with_timeout_or_null` returns the null
// sentinel instead. Call sites are rewritten by CoroutineLoweringPass to
// these cdecls with the block's suspend-entry point and the caller
// continuation; a Duration first argument is converted to milliseconds at
// the call site (`inWholeMilliseconds`), and the Int overload mirrors
// Kotlin's integer-literal adaptation, which this compiler's constraint
// solver does not perform.
//
// Passing `block` as a suspend-function *value* cannot supply an entry
// point to the bridge and remains unsupported, matching the pre-migration
// behaviour.

@KsSymbolName("kk_with_timeout")
public external suspend fun <T> withTimeout(timeMillis: Long, block: suspend () -> T): T

@KsSymbolName("kk_with_timeout_or_null")
public external suspend fun <T> withTimeoutOrNull(timeMillis: Long, block: suspend () -> T): T?

@KsSymbolName("kk_with_timeout")
public external suspend fun <T> withTimeout(timeMillis: Int, block: suspend () -> T): T

@KsSymbolName("kk_with_timeout_or_null")
public external suspend fun <T> withTimeoutOrNull(timeMillis: Int, block: suspend () -> T): T?

@KsSymbolName("kk_with_timeout")
public external suspend fun <T> withTimeout(duration: Duration, block: suspend () -> T): T

@KsSymbolName("kk_with_timeout_or_null")
public external suspend fun <T> withTimeoutOrNull(duration: Duration, block: suspend () -> T): T?
