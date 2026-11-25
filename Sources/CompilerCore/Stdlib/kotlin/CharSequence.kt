/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib core/builtins/native/kotlin/CharSequence.kt.
 */

package kotlin

public interface CharSequence {
    public val length: Int
    public operator fun get(index: Int): Char
    public fun subSequence(startIndex: Int, endIndex: Int): CharSequence
}
