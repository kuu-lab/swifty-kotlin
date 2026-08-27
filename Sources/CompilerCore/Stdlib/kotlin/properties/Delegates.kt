/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib commonMain/kotlin/properties/Delegates.kt.
 */

package kotlin.properties

import kotlin.reflect.KProperty

/**
 * `observable`/`vetoable` are implemented as named private subclasses of
 * [ObservableProperty] rather than the anonymous `object : ObservableProperty<T>(...) { ... }`
 * expression real kotlin-stdlib uses: anonymous object expressions inheriting
 * a class with an overridden member do not dispatch the override correctly
 * in this compiler, and forwarding constructor arguments through such an
 * expression crashes at runtime (tracked as a compiler capability gap
 * separate from KSP-491). Named class inheritance does not have either
 * problem, so it produces identical externally observable behavior.
 */
internal class SimpleObservableProperty<V>(
    initialValue: V,
    private val onChange: (property: KProperty<*>, oldValue: V, newValue: V) -> Unit
) : ObservableProperty<V>(initialValue) {
    override fun afterChange(property: KProperty<*>, oldValue: V, newValue: V) {
        onChange(property, oldValue, newValue)
    }
}

internal class SimpleVetoableProperty<V>(
    initialValue: V,
    private val onChange: (property: KProperty<*>, oldValue: V, newValue: V) -> Boolean
) : ObservableProperty<V>(initialValue) {
    override fun beforeChange(property: KProperty<*>, oldValue: V, newValue: V): Boolean {
        return onChange(property, oldValue, newValue)
    }
}

internal class NotNullVar<T : Any> : ReadWriteProperty<Any?, T> {
    private var value: T? = null

    public override fun getValue(thisRef: Any?, property: KProperty<*>): T {
        return value ?: throw IllegalStateException(
            "Property ${property.name} should be initialized before get."
        )
    }

    public override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
        this.value = value
    }
}

/**
 * Standard property delegate factories, as returned by [Delegates.observable],
 * [Delegates.vetoable] and [Delegates.notNull].
 */
public object Delegates {
    // `onChange` carries a default value even though it is conceptually
    // required: `by Delegates.observable(init) { ... }`'s trailing lambda is
    // parsed apart from this call (a compiler limitation tracked separately
    // from KSP-491, shared with `lazy { ... }`), so the call KIR lowering
    // sees here never actually includes it as an explicit argument -- lowering
    // supplies the real callback directly when constructing the delegate
    // object. The default only has to make plain (non-`by`) calls type-check.
    public fun <T> observable(
        initialValue: T,
        onChange: (property: KProperty<*>, oldValue: T, newValue: T) -> Unit = { _, _, _ -> }
    ): ReadWriteProperty<Any?, T> = SimpleObservableProperty(initialValue, onChange)

    public fun <T> vetoable(
        initialValue: T,
        onChange: (property: KProperty<*>, oldValue: T, newValue: T) -> Boolean = { _, _, _ -> true }
    ): ReadWriteProperty<Any?, T> = SimpleVetoableProperty(initialValue, onChange)

    public fun <T : Any> notNull(): ReadWriteProperty<Any?, T> = NotNullVar()
}
