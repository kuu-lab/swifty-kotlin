/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/properties/PropertyReferenceDelegates.kt.
 */

package kotlin

import kotlin.reflect.KMutableProperty0
import kotlin.reflect.KProperty

/**
 * Allows delegating a mutable receiverless property to a property reference.
 */
@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline operator fun <V> KMutableProperty0<V>.setValue(
    thisRef: Any?,
    property: KProperty<*>,
    value: V
) {
    set(value)
}
