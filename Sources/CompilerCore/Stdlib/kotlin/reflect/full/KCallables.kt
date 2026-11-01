/*
 * Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-reflect libraries/stdlib/.../kotlin/reflect/full/KCallables.kt.
 */

package kotlin.reflect.full

import kotlin.reflect.KCallable
import kotlin.reflect.KParameter

// A suspend callable reference has no reflection invoker (KCallable.call has
// no continuation), so it is invoked through its suspend function value.
@Suppress("UNCHECKED_CAST")
public suspend fun <R> KCallable<R>.callSuspend(vararg args: Any?): R {
    if (!isSuspend) return call(*args)
    return when (args.size) {
        0 -> (this as suspend () -> R)()
        1 -> (this as suspend (Any?) -> R)(args[0])
        2 -> (this as suspend (Any?, Any?) -> R)(args[0], args[1])
        3 -> (this as suspend (Any?, Any?, Any?) -> R)(args[0], args[1], args[2])
        4 -> (this as suspend (Any?, Any?, Any?, Any?) -> R)(args[0], args[1], args[2], args[3])
        5 -> (this as suspend (Any?, Any?, Any?, Any?, Any?) -> R)(args[0], args[1], args[2], args[3], args[4])
        else -> throw UnsupportedOperationException("callSuspend supports at most 5 arguments.")
    }
}

// Each `::f` evaluation mints its own KParameter objects, so keys match by
// position like the runtime callBy does. Omitted optional parameters need the
// reflection default-argument path.
public suspend fun <R> KCallable<R>.callSuspendBy(args: Map<KParameter, Any?>): R {
    if (!isSuspend) return callBy(args)
    val values = ArrayList<Any?>()
    for (parameter in parameters) {
        val entry = args.entries.firstOrNull {
            it.key == parameter || (it.key.index == parameter.index && it.key.name == parameter.name)
        } ?: return callBy(args)
        values.add(entry.value)
    }
    return callSuspend(*values.toTypedArray())
}
