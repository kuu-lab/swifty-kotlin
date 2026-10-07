/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/reflect/KProperty.kt.
 */

package kotlin.reflect

// KSP-682: KProperty0/1/2 and KMutableProperty0/1/2 public interface shells,
// migrated from synthetic Sema stubs (HeaderHelpers+SyntheticPropertyDelegateStubs)
// to bundled Kotlin source. The `() -> V` / `(T) -> V` / `(D, E) -> V` function-type
// supertypes (KSP-CAP-009) let property references be used as functions; Sema
// inheritance binding lowers them to the corresponding kotlin.Function{N} nominal
// interfaces. The KProperty / KMutableProperty bases were source-backed by
// KSP-1323 and live here as in upstream.

/**
 * Represents a property, accessible as a getter.
 */
public interface KProperty<out V> : KCallable<V> {
    public val isLateinit: Boolean
    public val isConst: Boolean
    public val getter: Getter<V>

    public interface Accessor<out V> {
        public val property: KProperty<V>
    }

    public interface Getter<out V> : Accessor<V>, KFunction<V>
}

/**
 * Represents a property which can be changed.
 */
public interface KMutableProperty<V> : KProperty<V> {
    public val setter: Setter<V>

    public interface Setter<V> : KProperty.Accessor<V>, KFunction<Unit>
}

public interface KProperty0<out V> : KProperty<V>, () -> V {
    public fun get(): V

    public fun getDelegate(): Any?

    override operator fun invoke(): V

    override val getter: Getter<V>
    public interface Getter<out V> : KProperty.Getter<V>, () -> V
}

public interface KMutableProperty0<V> : KProperty0<V>, KMutableProperty<V> {
    public fun set(value: V)

    override val setter: Setter<V>
    public interface Setter<V> : KMutableProperty.Setter<V>, (V) -> Unit
}

public interface KProperty1<T, out V> : KProperty<V>, (T) -> V {
    public fun get(receiver: T): V

    public fun getDelegate(receiver: T): Any?

    override operator fun invoke(p1: T): V

    override val getter: Getter<T, V>
    public interface Getter<T, out V> : KProperty.Getter<V>, (T) -> V
}

public interface KMutableProperty1<T, V> : KProperty1<T, V>, KMutableProperty<V> {
    public fun set(receiver: T, value: V)

    override val setter: Setter<T, V>
    public interface Setter<T, V> : KMutableProperty.Setter<V>, (T, V) -> Unit
}

public interface KProperty2<D, E, out V> : KProperty<V>, (D, E) -> V {
    public fun get(receiver1: D, receiver2: E): V

    public fun getDelegate(receiver1: D, receiver2: E): Any?

    override operator fun invoke(p1: D, p2: E): V

    override val getter: Getter<D, E, V>
    public interface Getter<D, E, out V> : KProperty.Getter<V>, (D, E) -> V
}

public interface KMutableProperty2<D, E, V> : KProperty2<D, E, V>, KMutableProperty<V> {
    public fun set(receiver1: D, receiver2: E, value: V)

    override val setter: Setter<D, E, V>
    public interface Setter<D, E, V> : KMutableProperty.Setter<V>, (D, E, V) -> Unit
}
