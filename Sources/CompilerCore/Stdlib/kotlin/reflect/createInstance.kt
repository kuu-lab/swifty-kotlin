/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/js/src/kotlin/reflect/createInstance.kt.
 */

package kotlin.reflect

import kotlin.js.ExperimentalJsReflectionCreateInstance
import kotlin.reflect.full.createInstance as createInstanceFromFull

// kotlin.reflect.full.createInstance is the canonical overload on JVM; keep
// this JS-derived mirror low-priority so `k.createInstance()` is unambiguous
// when both packages' extensions are visible (same duplicate-overload pattern
// as cast/safeCast, KUU-4046).
@kotlin.internal.LowPriorityInOverloadResolution
@ExperimentalJsReflectionCreateInstance
@SinceKotlin("1.9")
public fun <T : Any> KClass<T>.createInstance(): T = this.createInstanceFromFull()
