/*
 * Copyright 2016-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
@file:OptIn(ExperimentalMultiplatform::class)

package kotlinx.atomicfu

import kotlin.internal.InlineOnly

@Suppress("FunctionName")
public fun Trace(size: Int = 32, format: TraceFormat = traceFormatDefault): TraceBase = TraceBase.None

public fun TraceBase.named(name: String): TraceBase = TraceBase.None

public val traceFormatDefault: TraceFormat = TraceFormat()

@Suppress("DEPRECATION") @OptionalJsName(TRACE_BASE_CONSTRUCTOR)
public open class TraceBase internal constructor() {
    @OptionalJsName(TRACE_APPEND_1)
    public open fun append(event: Any) {}

    @OptionalJsName(TRACE_APPEND_2)
    public open fun append(event1: Any, event2: Any) {}

    @OptionalJsName(TRACE_APPEND_3)
    public open fun append(event1: Any, event2: Any, event3: Any) {}

    @OptionalJsName(TRACE_APPEND_4)
    public open fun append(event1: Any, event2: Any, event3: Any, event4: Any) {}

    @InlineOnly
    public inline operator fun invoke(event: () -> Any) {
        append(event())
    }

    public object None : TraceBase()
}
