/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib commonMain/kotlin/properties/Interfaces.kt.
 */

package kotlin.properties

import kotlin.reflect.KProperty

/**
 * Base interface for read-only property delegates.
 */
public fun interface ReadOnlyProperty<in T, out V> {
    public operator fun getValue(thisRef: T, property: KProperty<*>): V
}

/**
 * Base interface for read-write property delegates.
 */
public interface ReadWriteProperty<in T, V> : ReadOnlyProperty<T, V> {
    public override operator fun getValue(thisRef: T, property: KProperty<*>): V

    public operator fun setValue(thisRef: T, property: KProperty<*>, value: V)
}

/**
 * Base interface for property-delegate providers.
 */
public fun interface PropertyDelegateProvider<in T, out D> {
    public operator fun provideDelegate(thisRef: T, property: KProperty<*>): D
}
