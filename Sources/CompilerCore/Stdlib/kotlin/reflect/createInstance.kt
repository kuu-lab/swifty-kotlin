/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/js/src/kotlin/reflect/createInstance.kt.
 */

package kotlin.reflect

import kotlin.js.ExperimentalJsReflectionCreateInstance
import kotlin.reflect.full.createInstance as createInstanceFromFull

/**
 * Creates an instance by calling the single constructor that has no parameters or only parameters
 * with default values. Throws an exception when no such constructor or multiple such constructors
 * exist.
 */
@ExperimentalJsReflectionCreateInstance
@SinceKotlin("1.9")
public fun <T : Any> KClass<T>.createInstance(): T = this.createInstanceFromFull()
