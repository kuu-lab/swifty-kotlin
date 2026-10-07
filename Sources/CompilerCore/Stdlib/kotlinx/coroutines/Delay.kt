/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/Delay.kt.
 */
package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import kotlin.time.Duration

// KSP-1566 (KUU-902): `delay` was a synthetic top-level stub; it is bundled
// Kotlin now, mirroring upstream `Delay.kt`.
//
// Every overload is declared directly on the `kk_kxmini_delay` bridge. Suspend
// call sites receive the caller continuation as a trailing argument through
// the runtime-callee path in CoroutineLoweringPass; a Duration argument is
// converted to milliseconds at the call site (`inWholeMilliseconds`), and the
// Int overload mirrors Kotlin's integer-literal adaptation, which this
// compiler's constraint solver does not perform.

@KsSymbolName("kk_kxmini_delay")
public external suspend fun delay(timeMillis: Long): Unit

@KsSymbolName("kk_kxmini_delay")
public external suspend fun delay(timeMillis: Int): Unit

@KsSymbolName("kk_kxmini_delay")
public external suspend fun delay(duration: Duration): Unit

/** Context element that delays a coroutine, mirroring kotlinx.coroutines.Delay. */
public interface Delay : CoroutineContext.Element {
    public companion object Key : CoroutineContext.Key<Delay>
    public override val key: CoroutineContext.Key<*> get() = Key
}
