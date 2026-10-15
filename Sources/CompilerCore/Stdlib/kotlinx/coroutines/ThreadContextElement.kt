/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/ThreadContextElement.kt.
 */
package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext

public interface ThreadContextElement<S> : CoroutineContext.Element {
    public fun updateThreadContext(context: CoroutineContext): S

    public fun restoreThreadContext(context: CoroutineContext, oldState: S)
}

@DelicateCoroutinesApi
@ExperimentalCoroutinesApi
public interface CopyableThreadContextElement<S> : ThreadContextElement<S> {
    public fun copyForChild(): CopyableThreadContextElement<S>

    public fun mergeForChild(overwritingElement: CoroutineContext.Element): CoroutineContext
}
