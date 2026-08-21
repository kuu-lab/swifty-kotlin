/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/Tuples.kt.
 */

package kotlin

/**
 * Returns a copy of this pair with optionally replaced component values.
 */
public fun <A, B> Pair<A, B>.copy(first: A = this.first, second: B = this.second): Pair<A, B> =
    Pair(first, second)
