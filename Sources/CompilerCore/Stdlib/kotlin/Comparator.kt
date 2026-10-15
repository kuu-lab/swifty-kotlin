/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/Comparator.kt.
 */

package kotlin

// KSP-725: nominal `kotlin.Comparator<in T>` declaration migrated out of the
// synthetic self-registration.
public fun interface Comparator<in T> {
    public fun compare(a: T, b: T): Int

    public companion object {
        public fun <T> comparingInt(selector: (T) -> Int): Comparator<T> =
            Comparator { a, b -> selector(a).compareTo(selector(b)) }
    }
}
