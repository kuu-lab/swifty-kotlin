/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 */

@file:kotlin.jvm.JvmName("MapAccessorsKt")

package kotlin.collections

import kotlin.reflect.KProperty

public inline operator fun <V, V1 : V> Map<in String, V>.getValue(
    thisRef: Any?,
    property: KProperty<*>
): V1 {
    @Suppress("UNCHECKED_CAST")
    return getOrImplicitDefault(property.name) as V1
}

@kotlin.jvm.JvmName("getVar")
public inline operator fun <V, V1 : V> MutableMap<in String, out V>.getValue(
    thisRef: Any?,
    property: KProperty<*>
): V1 {
    @Suppress("UNCHECKED_CAST")
    return getOrImplicitDefault(property.name) as V1
}

public inline operator fun <V> MutableMap<in String, in V>.setValue(
    thisRef: Any?,
    property: KProperty<*>,
    value: V
) {
    put(property.name, value)
}
