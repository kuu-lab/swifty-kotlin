/*
 * Copyright 2010-2018 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-reflect libraries/stdlib/.../kotlin/reflect/full/KCallables.kt.
 */

package kotlin.reflect.full

import kotlin.reflect.KCallable
import kotlin.reflect.KParameter

/**
 * Calls a callable in the current suspend context. If the callable is not a suspend function, behaves as [KCallable.call].
 * Otherwise, calls the suspend function with current continuation.
 */
public suspend fun <R> KCallable<R>.callSuspend(vararg args: Any?): R =
    call(*args)

/**
 * Calls a callable in the current suspend context. If the callable is not a suspend function, behaves as [KCallable.callBy].
 * Otherwise, calls the suspend function with current continuation.
 */
public suspend fun <R> KCallable<R>.callSuspendBy(args: Map<KParameter, Any?>): R =
    callBy(args)
