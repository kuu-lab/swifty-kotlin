/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/properties/PropertyReferenceDelegates.kt>.
 */

package kotlin

import kotlin.reflect.KProperty
import kotlin.reflect.KProperty1

@SinceKotlin("1.4")
public inline operator fun <T, V> KProperty1<T, V>.getValue(
    thisRef: T,
    property: KProperty<*>
): V {
    return get(thisRef)
}
